import Foundation

/// Delegate kinds recognized by the compiler (P5-80, P5-79).
enum StdlibDelegateKind: Equatable {
    case lazy
    case observable
    case vetoable
    case notNull
    /// Custom user-defined delegate with getValue/setValue operators.
    case custom
}

/// Rewrites delegate property initialization sequences for known stdlib
/// delegates (`lazy`, `Delegates.observable`, `Delegates.vetoable`) into
/// direct runtime calls.
///
/// Must run **after** `PropertyLoweringPass` so that delegate accessor
/// calls have already been rewritten to direct getter/setter dispatches.
final class StdlibDelegateLoweringPass: LoweringPass {
    static let name = "StdlibDelegateLowering"

    func run(module: KIRModule, ctx: KIRContext) throws {
        let interner = ctx.interner
        let sema = ctx.sema
        let lazyCreateName = interner.intern("kk_lazy_create")
        let observableCreateName = interner.intern("kk_observable_create")
        let vetoableCreateName = interner.intern("kk_vetoable_create")
        let notNullCreateName = interner.intern("kk_notNull_create")

        let lazyThreadSafetyModeValue = Int64(ctx.options.lazyThreadSafetyMode.rawValue)

        // Build a mapping from $delegate_ field name → delegate kind.
        // We scan KIR function bodies for initialization patterns:
        //   .call(_, callee, ...) followed by .copy(_, to: $delegate_X)
        // This ensures each $delegate_ field is associated with the specific
        // factory function (lazy/observable/vetoable) that initializes it.
        var delegateKindByFieldName: [String: StdlibDelegateKind] = [:]
        if let sema {
            // Phase 1: scan KIR instructions to find call→copy patterns
            // that write to $delegate_ fields, and infer the delegate kind
            // from the callee or from sema call bindings on the call expr.
            module.arena.transformFunctions { function in
                let body = function.body
                for (index, instruction) in body.enumerated() {
                    guard case let .call(_, callee, _, _, _, _, _) = instruction else {
                        continue
                    }
                    let nextIndex = index + 1
                    guard nextIndex < body.count,
                          case let .copy(_, to) = body[nextIndex],
                          let toExpr = module.arena.expr(to),
                          case let .symbolRef(targetSym) = toExpr,
                          let targetSymInfo = sema.symbols.symbol(targetSym),
                          targetSymInfo.kind == .field
                    else {
                        continue
                    }
                    let fieldName = interner.resolve(targetSymInfo.name)
                    guard fieldName.hasPrefix("$delegate_"),
                          delegateKindByFieldName[fieldName] == nil
                    else {
                        continue
                    }
                    // Try to determine kind from the callee name directly.
                    let calleeName = interner.resolve(callee)
                    if let kind = delegateFactoryKind(calleeName) {
                        delegateKindByFieldName[fieldName] = kind
                    } else if calleeName == "kk_custom_delegate_create" {
                        delegateKindByFieldName[fieldName] = .custom
                    }
                }
                return function // no mutation in this scan pass
            }

            // Note: Previous "Phase 2" and "Phase 3" heuristics attempted to
            // derive $delegate_ field names from callee fqName components.
            // This produced names like `$delegate_kotlin`/`$delegate_Delegates`,
            // which do not match the actual `$delegate_<propertyName>` fields
            // created by MemberLowerer, so those phases have been removed.
        }

        module.arena.transformFunctions { function in
            var updated = function

            // Rewrite delegate initialization sequences.
            // Look for copy to $delegate_ fields preceded by a call, and wrap
            // with the appropriate kk_*_create runtime call.
            var finalBody: [KIRInstruction] = []
            finalBody.reserveCapacity(function.body.count)
            var skipNext = false

            for (index, instruction) in function.body.enumerated() {
                if skipNext {
                    skipNext = false
                    continue
                }

                if case let .call(_, _, callArgs, callResult, _, _, _) = instruction {
                    let nextIndex = index + 1
                    if nextIndex < function.body.count,
                       case let .copy(_, to) = function.body[nextIndex],
                       let toExpr = module.arena.expr(to),
                       case let .symbolRef(targetSym) = toExpr,
                       let targetSymInfo = sema?.symbols.symbol(targetSym),
                       targetSymInfo.kind == .field
                    {
                        let targetName = interner.resolve(targetSymInfo.name)
                        if targetName.hasPrefix("$delegate_"),
                           let kind = delegateKindByFieldName[targetName]
                        {
                            switch kind {
                            case .lazy:
                                guard !callArgs.isEmpty else { break }
                                let modeExpr = module.arena.appendExpr(
                                    .intLiteral(lazyThreadSafetyModeValue), type: nil
                                )
                                finalBody.append(.constValue(
                                    result: modeExpr,
                                    value: .intLiteral(lazyThreadSafetyModeValue)
                                ))
                                // Original factory call (lazy(...)) is intentionally
                                // NOT emitted — it references a synthetic stub with
                                // no runtime implementation.
                                let createResult = module.arena.appendExpr(
                                    .temporary(Int32(module.arena.expressions.count)),
                                    type: nil
                                )
                                finalBody.append(
                                    .call(
                                        symbol: nil,
                                        callee: lazyCreateName,
                                        arguments: [callArgs[0], modeExpr],
                                        result: createResult,
                                        canThrow: false,
                                        thrownResult: nil
                                    )
                                )
                                finalBody.append(.copy(from: createResult, to: to))
                                skipNext = true
                                continue
                            case .observable:
                                if callResult != nil {
                                    // Original factory call (Delegates.observable(...))
                                    // is intentionally NOT emitted — synthetic stub only.
                                    // kk_observable_create(initialValue, callbackFnPtr)
                                    // Strip the Delegates receiver (arg0) if present —
                                    // member call lowering inserts the receiver when the
                                    // callee has a receiverType.
                                    let createArgs = callArgs.count > 1 ? Array(callArgs.dropFirst()) : callArgs
                                    let createResult = module.arena.appendExpr(
                                        .temporary(Int32(module.arena.expressions.count)),
                                        type: nil
                                    )
                                    finalBody.append(
                                        .call(
                                            symbol: nil,
                                            callee: observableCreateName,
                                            arguments: createArgs,
                                            result: createResult,
                                            canThrow: false,
                                            thrownResult: nil
                                        )
                                    )
                                    finalBody.append(.copy(from: createResult, to: to))
                                    skipNext = true
                                    continue
                                }
                            case .vetoable:
                                if callResult != nil {
                                    // Original factory call (Delegates.vetoable(...))
                                    // is intentionally NOT emitted — synthetic stub only.
                                    // kk_vetoable_create(initialValue, callbackFnPtr)
                                    // Strip the Delegates receiver (arg0) if present.
                                    let createArgs = callArgs.count > 1 ? Array(callArgs.dropFirst()) : callArgs
                                    let createResult = module.arena.appendExpr(
                                        .temporary(Int32(module.arena.expressions.count)),
                                        type: nil
                                    )
                                    finalBody.append(
                                        .call(
                                            symbol: nil,
                                            callee: vetoableCreateName,
                                            arguments: createArgs,
                                            result: createResult,
                                            canThrow: false,
                                            thrownResult: nil
                                        )
                                    )
                                    finalBody.append(.copy(from: createResult, to: to))
                                    skipNext = true
                                    continue
                                }
                            case .notNull:
                                if callResult != nil {
                                    let createResult = module.arena.appendExpr(
                                        .temporary(Int32(module.arena.expressions.count)),
                                        type: nil
                                    )
                                    finalBody.append(
                                        .call(
                                            symbol: nil,
                                            callee: notNullCreateName,
                                            arguments: [],
                                            result: createResult,
                                            canThrow: false,
                                            thrownResult: nil
                                        )
                                    )
                                    finalBody.append(.copy(from: createResult, to: to))
                                    skipNext = true
                                    continue
                                }
                            case .custom:
                                // Custom delegates: the kk_custom_delegate_create
                                // call was already emitted by KIR lowering.
                                // Pass through as-is.
                                break
                            }
                        }
                    }
                }

                finalBody.append(instruction)
            }

            updated.replaceBody(finalBody)
            return updated
        }
        module.recordLowering(Self.name)
    }

    /// Returns the delegate kind for a known factory function name, or nil.
    private func delegateFactoryKind(_ name: String) -> StdlibDelegateKind? {
        switch name {
        case "lazy": .lazy
        case "observable": .observable
        case "vetoable": .vetoable
        case "notNull": .notNull
        default: nil
        }
    }
}
