import Foundation

final class PropertyLoweringPass: LoweringPass {
    static let name = "PropertyLowering"

    /// Lazily built reverse map from backing field symbol to its owning property symbol.
    private var backingFieldToPropertyMap: [SymbolID: SymbolID]?

    // swiftlint:disable:next cyclomatic_complexity function_body_length
    func run(module: KIRModule, ctx: KIRContext) throws {
        let getterName = ctx.interner.intern("get")
        let setterName = ctx.interner.intern("set")
        let getValueName = ctx.interner.intern("getValue")
        let setValueName = ctx.interner.intern("setValue")
        let interner = ctx.interner

        // Collect all function symbols emitted into the KIR module so we can
        // verify that a getter accessor actually exists before rewriting.
        let emittedFunctionSymbols: Set<SymbolID> = {
            var result = Set<SymbolID>()
            for decl in module.arena.declarations {
                if case let .function(fn) = decl {
                    result.insert(fn.symbol)
                }
            }
            return result
        }()

        // Build a set of getter-only computed property symbols (property kind,
        // no backing field, AND a getter accessor function exists in the module)
        // so that constValue(.symbolRef(propSym)) can be rewritten to a getter
        // call in the main transform loop.
        let computedPropertySymbols: Set<SymbolID> = {
            guard let sema = ctx.sema else { return [] }
            var result = Set<SymbolID>()
            for sym in sema.symbols.allSymbols() {
                guard sym.kind == .property,
                      sema.symbols.backingFieldSymbol(for: sym.id) == nil
                else {
                    continue
                }
                // Only include if a getter accessor function was actually
                // emitted — this avoids over-matching regular stored properties
                // that have no custom getter.
                let getterSymbol = SyntheticSymbolScheme.propertyGetterAccessorSymbol(for: sym.id)
                guard emittedFunctionSymbols.contains(getterSymbol) else {
                    continue
                }
                result.insert(sym.id)
            }
            return result
        }()

        module.arena.transformFunctions { function in
            var updated = function
            var loweredBody: [KIRInstruction] = []
            loweredBody.reserveCapacity(function.body.count)

            for instruction in function.body {
                guard case let .call(symbol, callee, arguments, result, canThrow, thrownResult, isSuperCall) = instruction else {
                    // Rewrite loadGlobal for getter-only computed properties
                    // into a getter call.  ExprLowerer emits loadGlobal for
                    // top-level property references; without this rewrite the
                    // backend would look for a non-existent global slot.
                    if case let .loadGlobal(lgResult, sym) = instruction,
                       computedPropertySymbols.contains(sym)
                    { // swiftlint:disable:this opening_brace
                        let getterSymbol = SyntheticSymbolScheme.propertyGetterAccessorSymbol(for: sym)
                        if function.symbol != getterSymbol {
                            loweredBody.append(
                                .call(
                                    symbol: getterSymbol,
                                    callee: getterName,
                                    arguments: [],
                                    result: lgResult,
                                    canThrow: false,
                                    thrownResult: nil
                                )
                            )
                            continue
                        }
                    }
                    // Rewrite constValue(.symbolRef(propSym)) for getter-only
                    // computed properties into a getter call so that each
                    // access invokes the getter body rather than loading a
                    // non-existent global.
                    if case let .constValue(cvResult, value) = instruction,
                       case let .symbolRef(sym) = value,
                       computedPropertySymbols.contains(sym)
                    { // swiftlint:disable:this opening_brace
                        // Skip rewriting if we are inside the getter accessor
                        // for this property to avoid infinite recursion.
                        let getterSymbol = SyntheticSymbolScheme.propertyGetterAccessorSymbol(for: sym)
                        if function.symbol != getterSymbol {
                            loweredBody.append(
                                .call(
                                    symbol: getterSymbol,
                                    callee: getterName,
                                    arguments: [],
                                    result: cvResult,
                                    canThrow: false,
                                    thrownResult: nil
                                )
                            )
                            continue
                        }
                    }
                    // Rewrite backing field copy instructions to direct
                    // setter accessor calls when the target is a backing
                    // field symbol.
                    if case let .copy(from, to) = instruction,
                       let sema = ctx.sema
                    { // swiftlint:disable:this opening_brace
                        let toExpr = module.arena.expr(to)
                        if case let .symbolRef(targetSym) = toExpr,
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
                            let setterSymbol = SyntheticSymbolScheme.propertySetterAccessorSymbol(for: baseSymbol)
                            // If the current function IS the setter accessor
                            // for this property, keep the original copy to
                            // avoid infinite recursion (setter calling itself).
                            if function.symbol == setterSymbol {
                                loweredBody.append(instruction)
                                continue
                            }
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
                if callee == getValueName || callee == setValueName,
                   let sema = ctx.sema,
                   let sym = symbol,
                   let symInfo = sema.symbols.symbol(sym),
                   symInfo.kind == .field,
                   interner.resolve(symInfo.name).hasPrefix("$delegate_") {
                    let isSetter = callee == setValueName
                    // Derive the property symbol from the delegate field name
                    // ($delegate_<propName> → <propName>). MemberLowerer creates
                    // accessor functions keyed off the property symbol, not the
                    // delegate storage field.
                    guard let propSymbol = self.propertySymbolForDelegateField(
                        sym, symInfo: symInfo, sema: sema, interner: interner
                    ) else {
                        // Cannot resolve property symbol — keep original call.
                        loweredBody.append(instruction)
                        continue
                    }
                    let accessorSymbol = isSetter
                        ? SyntheticSymbolScheme.propertySetterAccessorSymbol(for: propSymbol)
                        : SyntheticSymbolScheme.propertyGetterAccessorSymbol(for: propSymbol)
                    // If the current function IS the accessor being
                    // targeted, keep the original getValue/setValue call
                    // to avoid infinite recursion (accessor calling itself).
                    if function.symbol == accessorSymbol {
                        loweredBody.append(instruction)
                        continue
                    }
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
                if let sym = symbol {
                    let accessorSymbol = isSetter
                        ? SyntheticSymbolScheme.propertySetterAccessorSymbol(for: sym)
                        : SyntheticSymbolScheme.propertyGetterAccessorSymbol(for: sym)
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
        _: SymbolID,
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
