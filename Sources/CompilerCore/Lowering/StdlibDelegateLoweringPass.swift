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
        _ = interner.intern("kk_observable_create")
        let observableGetValueName = interner.intern("kk_observable_get_value")
        let observableSetValueName = interner.intern("kk_observable_set_value")
        _ = interner.intern("kk_vetoable_create")
        let vetoableGetValueName = interner.intern("kk_vetoable_get_value")
        let vetoableSetValueName = interner.intern("kk_vetoable_set_value")

        let lazyThreadSafetyModeValue = Int64(ctx.options.lazyThreadSafetyMode.rawValue)

        // Build a mapping from $delegate_ field name → delegate kind.
        // We inspect call bindings and identifier bindings in sema for known
        // stdlib delegate factory names, then tag all $delegate_ field symbols.
        var delegateKindByFieldName: [String: StdlibDelegateKind] = [:]
        if let sema {
            // Scan call bindings for known factory names.
            for (_, binding) in sema.bindings.callBindings {
                guard let calleeInfo = sema.symbols.symbol(binding.chosenCallee) else {
                    continue
                }
                let calleeName = interner.resolve(calleeInfo.name)
                if let kind = delegateFactoryKind(calleeName) {
                    markDelegateFields(
                        kind: kind, sema: sema, interner: interner,
                        into: &delegateKindByFieldName
                    )
                }
            }

            // Fallback: scan identifier bindings if no call bindings matched.
            if delegateKindByFieldName.isEmpty {
                for (_, sym) in sema.bindings.identifierSymbols {
                    guard let symInfo = sema.symbols.symbol(sym) else { continue }
                    let name = interner.resolve(symInfo.name)
                    if let kind = delegateFactoryKind(name) {
                        markDelegateFields(
                            kind: kind, sema: sema, interner: interner,
                            into: &delegateKindByFieldName
                        )
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
                let isSetter: Bool
                if let exprKind = module.arena.expr(isSetterExprID),
                   case .boolLiteral(let v) = exprKind {
                    isSetter = v
                } else {
                    isSetter = false
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

                if case .call(_, _, _, let callResult, _, _, _) = instruction {
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
                                let modeExpr = module.arena.appendExpr(
                                    .intLiteral(lazyThreadSafetyModeValue), type: nil
                                )
                                finalBody.append(.constValue(
                                    result: modeExpr,
                                    value: .intLiteral(lazyThreadSafetyModeValue)
                                ))
                                finalBody.append(instruction)
                                if let callResult {
                                    let createResult = module.arena.appendExpr(
                                        .temporary(Int32(module.arena.expressions.count)),
                                        type: nil
                                    )
                                    finalBody.append(
                                        .call(
                                            symbol: nil,
                                            callee: lazyCreateName,
                                            arguments: [callResult, modeExpr],
                                            result: createResult,
                                            canThrow: false,
                                            thrownResult: nil
                                        )
                                    )
                                    finalBody.append(.copy(from: createResult, to: to))
                                    skipNext = true
                                    continue
                                }
                            case .observable:
                                // observable/vetoable creation calls pass through.
                                break
                            case .vetoable:
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
        case "lazy": return .lazy
        case "observable": return .observable
        case "vetoable": return .vetoable
        default: return nil
        }
    }

    /// Tags all `$delegate_*` field symbols with the given delegate kind.
    private func markDelegateFields(
        kind: StdlibDelegateKind,
        sema: SemaModule,
        interner: StringInterner,
        into map: inout [String: StdlibDelegateKind]
    ) {
        for sym in sema.symbols.allSymbols() {
            guard sym.kind == .field else { continue }
            let name = interner.resolve(sym.name)
            guard name.hasPrefix("$delegate_") else { continue }
            if map[name] == nil {
                map[name] = kind
            }
        }
    }
}
