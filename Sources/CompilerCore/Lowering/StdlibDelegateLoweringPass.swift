import Foundation

/// Stdlib delegate kinds recognized by the compiler (P5-80).
enum StdlibDelegateKind: Equatable {
    case lazy
    case observable
    case vetoable
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
                    guard case .call(_, let callee, _, _, _, _, _) = instruction else {
                        continue
                    }
                    let nextIndex = index + 1
                    guard nextIndex < body.count,
                          case .copy(_, let to) = body[nextIndex],
                          let toExpr = module.arena.expr(to),
                          case .symbolRef(let targetSym) = toExpr,
                          let targetSymInfo = sema.symbols.symbol(targetSym),
                          targetSymInfo.kind == .field else {
                        continue
                    }
                    let fieldName = interner.resolve(targetSymInfo.name)
                    guard fieldName.hasPrefix("$delegate_"),
                          delegateKindByFieldName[fieldName] == nil else {
                        continue
                    }
                    // Try to determine kind from the callee name directly.
                    let calleeName = interner.resolve(callee)
                    if let kind = delegateFactoryKind(calleeName) {
                        delegateKindByFieldName[fieldName] = kind
                    }
                }
                return function // no mutation in this scan pass
            }

            // Phase 2: scan sema call bindings keyed by ExprID,
            // then match each factory call to its owning property's
            // $delegate_ field via the property's fqName.
            // Supplements Phase 1 to catch delegates where call→copy
            // adjacency doesn't hold (e.g. interleaved instructions).
            do {
                for (_, binding) in sema.bindings.callBindings {
                    guard let calleeInfo = sema.symbols.symbol(binding.chosenCallee) else {
                        continue
                    }
                    let calleeName = interner.resolve(calleeInfo.name)
                    guard let kind = delegateFactoryKind(calleeName) else { continue }

                    // Walk the callee's fqName ancestors to find the owning
                    // property, then derive the $delegate_ field name.
                    let fqName = calleeInfo.fqName
                    for ancestor in fqName.dropLast() {
                        let ancestorName = interner.resolve(ancestor)
                        let delegateFieldName = "$delegate_\(ancestorName)"
                        if delegateKindByFieldName[delegateFieldName] == nil {
                            // Verify this field actually exists in the symbol table.
                            let fieldExists = sema.symbols.allSymbols().contains {
                                $0.kind == .field && interner.resolve($0.name) == delegateFieldName
                            }
                            if fieldExists {
                                delegateKindByFieldName[delegateFieldName] = kind
                            }
                        }
                    }
                }
            }

            // Phase 3: scan identifier bindings for individual
            // factory references and match to their enclosing property.
            // Supplements Phases 1 & 2 for remaining undetected delegates.
            do {
                for (_, sym) in sema.bindings.identifierSymbols {
                    guard let symInfo = sema.symbols.symbol(sym) else { continue }
                    let name = interner.resolve(symInfo.name)
                    guard let kind = delegateFactoryKind(name) else { continue }
                    let fqName = symInfo.fqName
                    for ancestor in fqName.dropLast() {
                        let ancestorName = interner.resolve(ancestor)
                        let delegateFieldName = "$delegate_\(ancestorName)"
                        if delegateKindByFieldName[delegateFieldName] == nil {
                            let fieldExists = sema.symbols.allSymbols().contains {
                                $0.kind == .field && interner.resolve($0.name) == delegateFieldName
                            }
                            if fieldExists {
                                delegateKindByFieldName[delegateFieldName] = kind
                            }
                        }
                    }
                }
            }
        }

        module.arena.transformFunctions { function in
            var updated = function
            var loweredBody: [KIRInstruction] = []
            loweredBody.reserveCapacity(function.body.count)

            for instruction in function.body {
                guard case .call(let symbol, let callee, let arguments, let result, let canThrow, let thrownResult, let isSuperCall) = instruction else {
                    loweredBody.append(instruction)
                    continue
                }

                // Only rewrite kk_property_access calls on $delegate_ fields.
                guard callee == propertyAccessName,
                      let sym = symbol,
                      let symInfo = sema?.symbols.symbol(sym),
                      symInfo.kind == .field else {
                    loweredBody.append(instruction)
                    continue
                }

                let symName = interner.resolve(symInfo.name)
                guard symName.hasPrefix("$delegate_"),
                      let delegateKind = delegateKindByFieldName[symName] else {
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
                    if case .constValue(let result, let value) = prev,
                       result == isSetterExprID,
                       case .boolLiteral(let v) = value {
                        isSetter = v
                        break
                    }
                }

                // Build a symbol ref for the delegate handle.
                let delegateRef = module.arena.appendExpr(.symbolRef(sym), type: nil)
                loweredBody.append(.constValue(result: delegateRef, value: .symbolRef(sym)))

                switch delegateKind {
                case .lazy:
                    // lazy delegates are read-only: always emit kk_lazy_get_value.
                    loweredBody.append(
                        .call(
                            symbol: sym,
                            callee: lazyGetValueName,
                            arguments: [delegateRef],
                            result: result,
                            canThrow: canThrow,
                            thrownResult: thrownResult,
                            isSuperCall: isSuperCall
                        )
                    )

                case .observable:
                    if isSetter, arguments.count >= 2 {
                        loweredBody.append(
                            .call(
                                symbol: sym,
                                callee: observableSetValueName,
                                arguments: [delegateRef, arguments[1]],
                                result: result,
                                canThrow: canThrow,
                                thrownResult: thrownResult,
                                isSuperCall: isSuperCall
                            )
                        )
                    } else {
                        loweredBody.append(
                            .call(
                                symbol: sym,
                                callee: observableGetValueName,
                                arguments: [delegateRef],
                                result: result,
                                canThrow: canThrow,
                                thrownResult: thrownResult,
                                isSuperCall: isSuperCall
                            )
                        )
                    }

                case .vetoable:
                    if isSetter, arguments.count >= 2 {
                        loweredBody.append(
                            .call(
                                symbol: sym,
                                callee: vetoableSetValueName,
                                arguments: [delegateRef, arguments[1]],
                                result: result,
                                canThrow: canThrow,
                                thrownResult: thrownResult,
                                isSuperCall: isSuperCall
                            )
                        )
                    } else {
                        loweredBody.append(
                            .call(
                                symbol: sym,
                                callee: vetoableGetValueName,
                                arguments: [delegateRef],
                                result: result,
                                canThrow: canThrow,
                                thrownResult: thrownResult,
                                isSuperCall: isSuperCall
                            )
                        )
                    }
                }
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

                if case .call(_, _, let callArgs, let callResult, _, _, _) = instruction {
                    let nextIndex = index + 1
                    if nextIndex < loweredBody.count,
                       case .copy(_, let to) = loweredBody[nextIndex],
                       let toExpr = module.arena.expr(to),
                       case .symbolRef(let targetSym) = toExpr,
                       let targetSymInfo = sema?.symbols.symbol(targetSym),
                       targetSymInfo.kind == .field {
                        let targetName = interner.resolve(targetSymInfo.name)
                        if targetName.hasPrefix("$delegate_"),
                           let kind = delegateKindByFieldName[targetName] {
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
                                if let callResult {
                                    // Original factory call (Delegates.observable(...))
                                    // is intentionally NOT emitted — synthetic stub only.
                                    // kk_observable_create(initialValue, callbackFnPtr)
                                    // callArgs already contains the correct arguments.
                                    let createArgs = callArgs
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
                                if let callResult {
                                    // Original factory call (Delegates.vetoable(...))
                                    // is intentionally NOT emitted — synthetic stub only.
                                    // kk_vetoable_create(initialValue, callbackFnPtr)
                                    // callArgs already contains the correct arguments.
                                    let createArgs = callArgs
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
        case "lazy": return .lazy
        case "observable": return .observable
        case "vetoable": return .vetoable
        default: return nil
        }
    }

}
