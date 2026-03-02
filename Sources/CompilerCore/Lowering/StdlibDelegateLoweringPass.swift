import Foundation

/// Returns (getCallee, setCallee) for a delegate kind. Lazy is read-only so setCallee is nil.
private func delegateAccessorCallees(
    kind: StdlibDelegateKind,
    lazyGetValueName: InternedString,
    observableGetValueName: InternedString,
    observableSetValueName: InternedString,
    vetoableGetValueName: InternedString,
    vetoableSetValueName: InternedString,
    customGetValueName: InternedString,
    customSetValueName: InternedString
) -> (getCallee: InternedString, setCallee: InternedString?) {
    switch kind {
    case .lazy:
        (lazyGetValueName, nil)
    case .observable:
        (observableGetValueName, observableSetValueName)
    case .vetoable:
        (vetoableGetValueName, vetoableSetValueName)
    case .custom:
        (customGetValueName, customSetValueName)
    }
}

/// Delegate kinds recognized by the compiler (P5-80, P5-79).
enum StdlibDelegateKind: Equatable {
    case lazy
    case observable
    case vetoable
    /// Custom user-defined delegate with getValue/setValue operators.
    case custom
}

/// Rewrites delegate property accesses for known stdlib delegates
/// (`lazy`, `Delegates.observable`, `Delegates.vetoable`) into direct
/// runtime calls, replacing the generic `kk_property_access` emitted by
/// `PropertyLoweringPass`.
///
/// Must run **after** `PropertyLoweringPass` so that `getValue`/`setValue`
/// have already been rewritten to `kk_property_access`.
final class StdlibDelegateLoweringPass: LoweringPass {
    static let name = "StdlibDelegateLowering"

    func run(module: KIRModule, ctx: KIRContext) throws {
        let interner = ctx.interner
        let sema = ctx.sema
        let propertyAccessName = interner.intern("kk_property_access")
        let lazyCreateName = interner.intern("kk_lazy_create")
        let lazyGetValueName = interner.intern("kk_lazy_get_value")
        let observableCreateName = interner.intern("kk_observable_create")
        let observableGetValueName = interner.intern("kk_observable_get_value")
        let observableSetValueName = interner.intern("kk_observable_set_value")
        let vetoableCreateName = interner.intern("kk_vetoable_create")
        let vetoableGetValueName = interner.intern("kk_vetoable_get_value")
        let vetoableSetValueName = interner.intern("kk_vetoable_set_value")
        let customGetValueName = interner.intern("kk_custom_delegate_get_value")
        let customSetValueName = interner.intern("kk_custom_delegate_set_value")

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
            var loweredBody: [KIRInstruction] = []
            loweredBody.reserveCapacity(function.body.count)

            for instruction in function.body {
                guard case let .call(symbol, callee, arguments, result, canThrow, thrownResult, isSuperCall) = instruction else {
                    loweredBody.append(instruction)
                    continue
                }

                // Only rewrite kk_property_access calls on $delegate_ fields.
                guard callee == propertyAccessName,
                      let sym = symbol,
                      let symInfo = sema?.symbols.symbol(sym),
                      symInfo.kind == .field
                else {
                    loweredBody.append(instruction)
                    continue
                }

                let symName = interner.resolve(symInfo.name)
                guard symName.hasPrefix("$delegate_"),
                      let delegateKind = delegateKindByFieldName[symName]
                else {
                    loweredBody.append(instruction)
                    continue
                }

                // arguments[0] = isSetter flag (constValue bool).
                guard arguments.count >= 1 else {
                    loweredBody.append(instruction)
                    continue
                }

                let isSetterExprID = arguments[0]
                var isSetter = false
                // The accessor-kind bool is stored in a .constValue instruction
                // (not in the arena expression which is .temporary), so scan
                // backward through already-lowered instructions to find it.
                for prev in loweredBody.reversed() {
                    if case let .constValue(result, value) = prev,
                       result == isSetterExprID,
                       case let .boolLiteral(v) = value
                    {
                        isSetter = v
                        break
                    }
                }

                // Build a symbol ref for the delegate handle.
                let delegateRef = module.arena.appendExpr(.symbolRef(sym), type: nil)
                loweredBody.append(.constValue(result: delegateRef, value: .symbolRef(sym)))

                let (getCallee, setCallee) = delegateAccessorCallees(
                    kind: delegateKind,
                    lazyGetValueName: lazyGetValueName,
                    observableGetValueName: observableGetValueName,
                    observableSetValueName: observableSetValueName,
                    vetoableGetValueName: vetoableGetValueName,
                    vetoableSetValueName: vetoableSetValueName,
                    customGetValueName: customGetValueName,
                    customSetValueName: customSetValueName
                )
                let accessorCallee: InternedString
                let callArgs: [KIRExprID]
                if isSetter, arguments.count >= 2, let setCallee {
                    accessorCallee = setCallee
                    callArgs = [delegateRef, arguments[1]]
                } else {
                    accessorCallee = getCallee
                    callArgs = [delegateRef]
                }
                loweredBody.append(
                    .call(
                        symbol: sym,
                        callee: accessorCallee,
                        arguments: callArgs,
                        result: result,
                        canThrow: canThrow,
                        thrownResult: thrownResult,
                        isSuperCall: isSuperCall
                    )
                )
            }

            // Second pass: rewrite delegate initialization sequences.
            // Look for copy to $delegate_ fields preceded by a call, and wrap
            // with the appropriate kk_*_create runtime call.
            var finalBody: [KIRInstruction] = []
            finalBody.reserveCapacity(loweredBody.count)
            var skipNext = false

            for (index, instruction) in loweredBody.enumerated() {
                if skipNext {
                    skipNext = false
                    continue
                }

                if case let .call(_, _, callArgs, callResult, _, _, _) = instruction {
                    let nextIndex = index + 1
                    if nextIndex < loweredBody.count,
                       case let .copy(_, to) = loweredBody[nextIndex],
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

            updated.body = finalBody
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
        default: nil
        }
    }
}
