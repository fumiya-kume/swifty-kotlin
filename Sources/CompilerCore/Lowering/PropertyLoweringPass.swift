import Foundation

final class PropertyLoweringPass: LoweringPass {
    static let name = "PropertyLowering"

    /// Lazily built reverse map from backing field symbol to its owning property symbol.
    private var backingFieldToPropertyMap: [SymbolID: SymbolID]?

    func run(module: KIRModule, ctx: KIRContext) throws {
        let getterName = ctx.interner.intern("get")
        let setterName = ctx.interner.intern("set")
        let getValueName = ctx.interner.intern("getValue")
        let setValueName = ctx.interner.intern("setValue")
        let interner = ctx.interner

        module.arena.transformFunctions { function in
            var updated = function
            var loweredBody: [KIRInstruction] = []
            loweredBody.reserveCapacity(function.body.count)

            for instruction in function.body {
                guard case .call(let symbol, let callee, let arguments, let result, let canThrow, let thrownResult, let isSuperCall) = instruction else {
                    // Rewrite backing field copy instructions to direct
                    // setter accessor calls when the target is a backing
                    // field symbol.
                    if case .copy(let from, let to) = instruction,
                       let sema = ctx.sema {
                        let toExpr = module.arena.expr(to)
                        if case .symbolRef(let targetSym) = toExpr,
                           sema.symbols.symbol(targetSym)?.kind == .backingField {
                            // Find the property symbol that owns this backing
                            // field and emit a direct setter accessor call.
                            let propSym = self.propertySymbolForBackingField(
                                targetSym, sema: sema
                            )
                            guard let baseSymbol = propSym else {
                                // Cannot find owning property — keep original copy.
                                loweredBody.append(instruction)
                                continue
                            }
                            let setterSymbol = SymbolID(
                                rawValue: -13_000 - baseSymbol.rawValue
                            )
                            loweredBody.append(
                                .call(
                                    symbol: setterSymbol,
                                    callee: setterName,
                                    arguments: [from],
                                    result: nil,
                                    canThrow: false,
                                    thrownResult: nil
                                )
                            )
                            continue
                        }
                    }
                    loweredBody.append(instruction)
                    continue
                }

                // Lower delegated property getValue/setValue calls to
                // direct accessor calls with the delegate-aware signature.
                // Only rewrite calls whose symbol is a delegate storage field
                // (name starts with $delegate_) to avoid rewriting user-defined
                // getValue/setValue methods.
                if (callee == getValueName || callee == setValueName),
                   let sema = ctx.sema,
                   let sym = symbol,
                   let symInfo = sema.symbols.symbol(sym),
                   symInfo.kind == .field,
                   interner.resolve(symInfo.name).hasPrefix("$delegate_") {
                    let isSetter = callee == setValueName
                    let accessorSymbolOffset: Int32 = isSetter ? -13_000 : -12_000
                    // Derive the property symbol from the delegate field name
                    // ($delegate_<propName> → <propName>). MemberLowerer creates
                    // accessor functions keyed off the property symbol, not the
                    // delegate storage field.
                    let propSymbol = self.propertySymbolForDelegateField(
                        sym, symInfo: symInfo, sema: sema, interner: interner
                    ) ?? sym
                    let accessorSymbol = SymbolID(rawValue: accessorSymbolOffset - propSymbol.rawValue)
                    loweredBody.append(
                        .call(
                            symbol: accessorSymbol,
                            callee: isSetter ? setterName : getterName,
                            arguments: arguments,
                            result: result,
                            canThrow: canThrow,
                            thrownResult: thrownResult,
                            isSuperCall: isSuperCall
                        )
                    )
                    continue
                }

                guard callee == getterName || callee == setterName else {
                    loweredBody.append(instruction)
                    continue
                }

                // Rewrite get/set calls to use the synthetic accessor
                // symbol for direct dispatch, eliminating the
                // kk_property_access indirection and accessor-kind
                // boolean argument.
                let isSetter = callee == setterName
                let accessorSymbolOffset: Int32 = isSetter ? -13_000 : -12_000
                if let sym = symbol {
                    let accessorSymbol = SymbolID(rawValue: accessorSymbolOffset - sym.rawValue)
                    loweredBody.append(
                        .call(
                            symbol: accessorSymbol,
                            callee: callee,
                            arguments: arguments,
                            result: result,
                            canThrow: canThrow,
                            thrownResult: thrownResult,
                            isSuperCall: isSuperCall
                        )
                    )
                } else {
                    // No property symbol — keep original instruction.
                    loweredBody.append(instruction)
                }
            }

            updated.body = loweredBody
            return updated
        }
        module.recordLowering(Self.name)
    }

    /// Given a backing field symbol, find the property symbol it belongs to.
    /// Uses a lazily built reverse map for O(1) lookups after the first call.
    private func propertySymbolForBackingField(
        _ backingFieldSymbol: SymbolID,
        sema: SemaModule
    ) -> SymbolID? {
        if backingFieldToPropertyMap == nil {
            var map: [SymbolID: SymbolID] = [:]
            for sym in sema.symbols.allSymbols() {
                if let backing = sema.symbols.backingFieldSymbol(for: sym.id) {
                    map[backing] = sym.id
                }
            }
            backingFieldToPropertyMap = map
        }
        return backingFieldToPropertyMap?[backingFieldSymbol]
    }

    /// Given a delegate storage field symbol ($delegate_<name>), find the
    /// property symbol it belongs to by stripping the prefix and looking
    /// up a sibling symbol with the property name.
    private func propertySymbolForDelegateField(
        _ delegateFieldSymbol: SymbolID,
        symInfo: SemanticSymbol,
        sema: SemaModule,
        interner: StringInterner
    ) -> SymbolID? {
        let delegateName = interner.resolve(symInfo.name)
        guard delegateName.hasPrefix("$delegate_") else { return nil }
        let propertyName = String(delegateName.dropFirst("$delegate_".count))
        let internedPropName = interner.intern(propertyName)
        // Look up a sibling with the matching property name in the
        // same parent scope (same fqName prefix).
        let parentFQ = symInfo.fqName.dropLast()
        let propFQ = Array(parentFQ) + [internedPropName]
        return sema.symbols.lookup(fqName: propFQ)
    }
}
