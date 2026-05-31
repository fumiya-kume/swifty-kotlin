import Foundation

final class DataEnumSealedSynthesisPass: LoweringPass {
    static let name = "DataEnumSealedSynthesis"

    func run(module: KIRModule, ctx: KIRContext) throws {
        module.arena.transformFunctions { function in
            var updated = function
            if updated.body.isEmpty {
                updated.replaceBody([.nop, .returnUnit])
            }
            return updated
        }

        guard let sema = ctx.sema else {
            module.recordLowering(Self.name)
            return
        }

        let intType = sema.types.make(.primitive(.int, .nonNull))
        let existingFunctionSymbols = Set(module.arena.declarations.compactMap { decl -> SymbolID? in
            guard case let .function(function) = decl else {
                return nil
            }
            return function.symbol
        })
        let nominalSymbols = module.arena.declarations.compactMap { decl -> SymbolID? in
            guard case let .nominalType(nominal) = decl else {
                return nil
            }
            return nominal.symbol
        }

        for nominalSymbolID in nominalSymbols {
            guard let nominalSymbol = sema.symbols.symbol(nominalSymbolID) else {
                continue
            }
            if nominalSymbol.kind == .enumClass {
                synthesizeEnumHelpers(
                    nominalSymbol: nominalSymbol, intType: intType,
                    module: module, sema: sema,
                    existingFunctionSymbols: existingFunctionSymbols, ctx: ctx
                )
            }
            if nominalSymbol.flags.contains(.sealedType) {
                synthesizeSealedHelper(
                    nominalSymbol: nominalSymbol, intType: intType,
                    module: module, sema: sema,
                    existingFunctionSymbols: existingFunctionSymbols, ctx: ctx
                )
            }
            if nominalSymbol.flags.contains(.dataType) {
                synthesizeDataHelpers(
                    nominalSymbol: nominalSymbol,
                    module: module, sema: sema,
                    existingFunctionSymbols: existingFunctionSymbols, ctx: ctx
                )
            }
        }

        // Rewrite symbolRef references to synthetic enum entries (e.g.
        // RegexOption.DOT_MATCHES_ALL) into boxed ordinal int literals.
        // User-defined enum entries are backed by global variables, but
        // synthetic entries have no globals — so we inline the ordinal.
        rewriteSyntheticEnumEntryRefs(module: module, sema: sema)

        module.recordLowering(Self.name)
    }

    /// Replaces `constValue(result: r, value: .symbolRef(sym))` where `sym`
    /// is a synthetic field owned by a synthetic enum class with
    /// `constValue(result: r, value: .intLiteral(ordinal))` followed by a
    /// `call kk_box_int` so the value is a boxed enum ordinal.
    private func rewriteSyntheticEnumEntryRefs(
        module: KIRModule,
        sema: SemaModule
    ) {
        // Build a lookup: syntheticEnumEntrySymbol -> ordinal
        var syntheticEntryOrdinal: [SymbolID: Int] = [:]
        for sym in sema.symbols.allSymbols() {
            guard sym.kind == .field,
                  sym.flags.contains(.synthetic),
                  sym.fqName.count >= 2
            else {
                continue
            }
            let parentFQ = Array(sym.fqName.dropLast())
            guard let parentSymbol = sema.symbols.lookup(fqName: parentFQ),
                  let parentInfo = sema.symbols.symbol(parentSymbol),
                  parentInfo.kind == .enumClass,
                  parentInfo.flags.contains(.synthetic)
            else {
                continue
            }
            // Ordinal = index among all field children of the parent enum.
            let siblings = sema.symbols.children(ofFQName: parentFQ)
                .filter { id in
                    guard let s = sema.symbols.symbol(id) else { return false }
                    return s.kind == .field
                }
                .sorted(by: { $0.rawValue < $1.rawValue })
            if let ordinal = siblings.firstIndex(of: sym.id) {
                syntheticEntryOrdinal[sym.id] = ordinal
            }
        }
        guard !syntheticEntryOrdinal.isEmpty else { return }

        module.arena.transformFunctions { function in
            var newBody: [KIRInstruction] = []
            var changed = false
            for instruction in function.body {
                guard case let .constValue(result, .symbolRef(sym)) = instruction,
                      let ordinal = syntheticEntryOrdinal[sym]
                else {
                    newBody.append(instruction)
                    continue
                }
                changed = true
                // Replace the symbolRef with a raw ordinal int literal,
                // matching how all other enum synthesis paths represent entries.
                newBody.append(.constValue(result: result, value: .intLiteral(Int64(ordinal))))
            }
            if changed {
                var updated = function
                updated.replaceBody(newBody)
                return updated
            }
            return function
        }
    }

    private func synthesizeEnumHelpers(
        nominalSymbol: SemanticSymbol,
        intType: TypeID,
        module: KIRModule,
        sema: SemaModule,
        existingFunctionSymbols: Set<SymbolID>,
        ctx: KIRContext
    ) {
        let entries = enumEntrySymbols(owner: nominalSymbol, symbols: sema.symbols)
        let helperName = ctx.interner.intern("\(ctx.interner.resolve(nominalSymbol.name))$enumValuesCount")
        appendSyntheticCountFunctionIfNeeded(
            name: helperName, owner: nominalSymbol, value: Int64(entries.count),
            returnType: intType, module: module, sema: sema,
            existingFunctionSymbols: existingFunctionSymbols
        )
        let stringType = sema.types.make(.primitive(.string, .nonNull))
        for (ordinal, entry) in entries.enumerated() {
            let entryName = ctx.interner.resolve(entry.name)
            appendSyntheticCountFunctionIfNeeded(
                name: ctx.interner.intern("\(entryName)$enumOrdinal"),
                owner: nominalSymbol, value: Int64(ordinal),
                returnType: intType, module: module, sema: sema,
                existingFunctionSymbols: existingFunctionSymbols
            )
            appendSyntheticStringFunctionIfNeeded(
                name: ctx.interner.intern("\(entryName)$enumName"),
                owner: nominalSymbol, value: ctx.interner.intern(entryName),
                returnType: stringType, module: module, sema: sema,
                existingFunctionSymbols: existingFunctionSymbols
            )
        }
        appendSyntheticEnumValuesIfNeeded(
            name: ctx.interner.intern("values"), owner: nominalSymbol,
            entries: entries,
            module: module, sema: sema, existingFunctionSymbols: existingFunctionSymbols,
            interner: ctx.interner
        )
        appendSyntheticEnumOrdinalToNameIfNeeded(
            owner: nominalSymbol,
            entries: entries,
            module: module,
            sema: sema,
            existingFunctionSymbols: existingFunctionSymbols,
            interner: ctx.interner
        )
        // valueOf and entries live on the companion (Color.valueOf, Color.entries)
        let valueOfOwner: SemanticSymbol = if let companionSymbol = sema.symbols.companionObjectSymbol(for: nominalSymbol.id),
                                              let companionSym = sema.symbols.symbol(companionSymbol)
        {
            companionSym
        } else {
            nominalSymbol
        }
        appendSyntheticEnumEntriesGetterIfNeeded(
            owner: valueOfOwner,
            enumSymbol: nominalSymbol,
            entries: entries,
            module: module,
            sema: sema,
            existingFunctionSymbols: existingFunctionSymbols,
            interner: ctx.interner
        )
        appendSyntheticEnumValueOfIfNeeded(
            name: ctx.interner.intern("valueOf"),
            owner: valueOfOwner,
            enumName: nominalSymbol.name,
            enumType: sema.types.make(.classType(ClassType(
                classSymbol: nominalSymbol.id,
                args: [],
                nullability: .nonNull
            ))),
            entries: entries,
            module: module,
            sema: sema,
            existingFunctionSymbols: existingFunctionSymbols,
            interner: ctx.interner
        )
        appendSyntheticEnumStaticInitIfNeeded(
            owner: nominalSymbol,
            entries: entries,
            module: module,
            sema: sema,
            existingFunctionSymbols: existingFunctionSymbols,
            interner: ctx.interner
        )
    }

    private func synthesizeSealedHelper(
        nominalSymbol: SemanticSymbol,
        intType: TypeID,
        module: KIRModule,
        sema: SemaModule,
        existingFunctionSymbols: Set<SymbolID>,
        ctx: KIRContext
    ) {
        let subtypeCount = Int64(sema.symbols.directSubtypes(of: nominalSymbol.id).count)
        let helperName = ctx.interner.intern("\(ctx.interner.resolve(nominalSymbol.name))$sealedSubtypeCount")
        appendSyntheticCountFunctionIfNeeded(
            name: helperName, owner: nominalSymbol, value: subtypeCount,
            returnType: intType, module: module, sema: sema,
            existingFunctionSymbols: existingFunctionSymbols
        )
    }

    private func synthesizeDataHelpers(
        nominalSymbol: SemanticSymbol,
        module: KIRModule,
        sema: SemaModule,
        existingFunctionSymbols: Set<SymbolID>,
        ctx: KIRContext
    ) {
        let copyName = ctx.interner.intern("copy")
        let existingCopySymbol = sema.symbols.lookupAll(fqName: nominalSymbol.fqName + [copyName]).first {
            sema.symbols.symbol($0).map { $0.flags.contains(.synthetic) } ?? false
        }
        appendSyntheticDataCopyIfNeeded(
            name: copyName,
            owner: nominalSymbol, module: module, sema: sema,
            existingSymbol: existingCopySymbol,
            existingFunctionSymbols: existingFunctionSymbols, interner: ctx.interner,
            diagnostics: ctx.diagnostics
        )
        if nominalSymbol.kind == .class {
            let hashCodeName = ctx.interner.intern("hashCode")
            let existingHashCodeSymbol = sema.symbols.lookupAll(fqName: nominalSymbol.fqName + [hashCodeName]).first {
                sema.symbols.symbol($0).map { $0.flags.contains(.synthetic) } ?? false
            }
            appendSyntheticDataClassHashCodeIfNeeded(
                owner: nominalSymbol, existingSymbol: existingHashCodeSymbol,
                module: module, sema: sema,
                existingFunctionSymbols: existingFunctionSymbols, interner: ctx.interner
            )
        }
        synthesizeDataClassComponentN(
            nominalSymbol: nominalSymbol,
            module: module,
            sema: sema,
            existingFunctionSymbols: existingFunctionSymbols,
            ctx: ctx
        )
        let toStringName = ctx.interner.intern("toString")
        let existingToStringSymbol = sema.symbols.lookupAll(fqName: nominalSymbol.fqName + [toStringName]).first {
            sema.symbols.symbol($0).map { $0.flags.contains(.synthetic) } ?? false
        }
        let equalsName = ctx.interner.intern("equals")
        let existingEqualsSymbol = sema.symbols.lookupAll(fqName: nominalSymbol.fqName + [equalsName]).first {
            sema.symbols.symbol($0).map { $0.flags.contains(.synthetic) } ?? false
        }

        if nominalSymbol.kind == .object {
            appendSyntheticDataObjectToStringIfNeeded(
                name: toStringName, owner: nominalSymbol, objectName: nominalSymbol.name,
                existingSymbol: existingToStringSymbol, module: module, sema: sema,
                existingFunctionSymbols: existingFunctionSymbols, interner: ctx.interner
            )
            appendSyntheticDataObjectEqualsIfNeeded(
                owner: nominalSymbol, existingSymbol: existingEqualsSymbol,
                module: module, sema: sema,
                existingFunctionSymbols: existingFunctionSymbols, interner: ctx.interner
            )
        } else if nominalSymbol.kind == .class {
            let properties = dataClassPropertySymbols(owner: nominalSymbol, symbols: sema.symbols)
            appendSyntheticDataClassToStringIfNeeded(
                name: toStringName, owner: nominalSymbol, properties: properties,
                existingSymbol: existingToStringSymbol, module: module, sema: sema,
                existingFunctionSymbols: existingFunctionSymbols, interner: ctx.interner
            )
            appendSyntheticDataClassEqualsIfNeeded(
                owner: nominalSymbol, properties: properties,
                existingSymbol: existingEqualsSymbol, module: module, sema: sema,
                existingFunctionSymbols: existingFunctionSymbols, interner: ctx.interner
            )
        }
    }

    /// Returns the primary-constructor data properties of a data class, sorted by constructor order.
    private func dataClassPropertySymbols(owner: SemanticSymbol, symbols: SymbolTable) -> [SemanticSymbol] {
        let primaryConstructorParamNames: [InternedString] = primaryConstructorSymbol(owner: owner, symbols: symbols)
            .flatMap { constructor in
                symbols.functionSignature(for: constructor.id)?.valueParameterSymbols.compactMap { paramSymbol in
                    symbols.symbol(paramSymbol)?.name
                }
            } ?? []
        guard !primaryConstructorParamNames.isEmpty else {
            return []
        }

        let propertiesByName = Dictionary(
            symbols.children(ofFQName: owner.fqName)
                .compactMap { symbols.symbol($0) }
                .filter { $0.kind == .property && !$0.flags.contains(.synthetic) }
                .map { ($0.name, $0) },
            uniquingKeysWith: { first, _ in first }
        )
        return primaryConstructorParamNames.compactMap { propertiesByName[$0] }
    }

    private func primaryConstructorSymbol(owner: SemanticSymbol, symbols: SymbolTable) -> SemanticSymbol? {
        symbols.children(ofFQName: owner.fqName)
            .compactMap { symbols.symbol($0) }
            .filter { $0.kind == .constructor }
            .min { lhs, rhs in
                let lhsOffset = lhs.declSite?.start.offset ?? Int.max
                let rhsOffset = rhs.declSite?.start.offset ?? Int.max
                if lhsOffset != rhsOffset {
                    return lhsOffset < rhsOffset
                }
                return lhs.id.rawValue < rhs.id.rawValue
            }
    }

    func anyToStringTag(for type: TypeID, sema: SemaModule) -> Int64 {
        switch sema.types.kind(of: sema.types.makeNonNullable(type)) {
        case .primitive(.boolean, _):
            2
        case .primitive(.string, _):
            3
        default:
            1
        }
    }

    /// DATA-002 / STDLIB-090: Synthesizes `componentN()` KIR function bodies for data classes.
    /// Each componentN takes the receiver ($self) and returns the Nth constructor property
    /// by reading the corresponding field via `kk_array_get_inbounds`.
    private func synthesizeDataClassComponentN(
        nominalSymbol: SemanticSymbol,
        module: KIRModule,
        sema: SemaModule,
        existingFunctionSymbols: Set<SymbolID>,
        ctx: KIRContext
    ) {
        let interner = ctx.interner

        let componentSymbols = syntheticDataClassComponentSymbols(
            owner: nominalSymbol,
            sema: sema,
            interner: interner
        )

        guard !componentSymbols.isEmpty else { return }

        let propertySymbols = primaryConstructorPropertySymbols(
            owner: nominalSymbol,
            sema: sema
        )

        let layout = sema.symbols.nominalLayout(for: nominalSymbol.id)

        for (componentIndex, functionSymbol, signature) in componentSymbols {
            guard !existingFunctionSymbols.contains(functionSymbol) else { continue }

            let componentName = interner.intern("component\(componentIndex)")
            let returnType = signature.returnType
            let fqName = nominalSymbol.fqName + [componentName]
            let receiverType = signature.receiverType ?? sema.types.make(.classType(ClassType(
                classSymbol: nominalSymbol.id,
                args: [],
                nullability: .nonNull
            )))

            // Create receiver parameter ($self)
            let selfParamName = interner.intern("$self")
            let selfParamSymbol = sema.symbols.define(
                kind: .valueParameter,
                name: selfParamName,
                fqName: fqName + [selfParamName],
                declSite: nominalSymbol.declSite,
                visibility: .private,
                flags: [.synthetic]
            )
            let selfParam = KIRParameter(symbol: selfParamSymbol, type: receiverType)

            let selfRef = module.arena.appendExpr(.symbolRef(selfParamSymbol), type: receiverType)

            var body: [KIRInstruction] = []
            body.append(.constValue(result: selfRef, value: .symbolRef(selfParamSymbol)))

            let propertyIndex = componentIndex - 1 // 0-based
            let resultExpr = module.arena.appendExpr(
                .temporary(Int32(module.arena.expressions.count)),
                type: returnType
            )

            // Read the primary-constructor-backed field via layout offset.
            if let layout = layout,
               propertyIndex < propertySymbols.count,
               let propertySymbol = propertySymbols[propertyIndex]
            {
                let backingField = sema.symbols.backingFieldSymbol(for: propertySymbol.id) ?? propertySymbol.id
                if let fieldOffset = layout.fieldOffsets[backingField] ?? layout.fieldOffsets[propertySymbol.id] {
                    let offsetExpr = module.arena.appendExpr(
                        .intLiteral(Int64(fieldOffset)),
                        type: sema.types.make(.primitive(.int, .nonNull))
                    )
                    body.append(.constValue(result: offsetExpr, value: .intLiteral(Int64(fieldOffset))))
                    body.append(.call(
                        symbol: nil,
                        callee: interner.intern("kk_array_get_inbounds"),
                        arguments: [selfRef, offsetExpr],
                        result: resultExpr,
                        canThrow: false,
                        thrownResult: nil
                    ))
                    body.append(.returnValue(resultExpr))
                    appendSyntheticFunctionWithSymbol(
                        functionSymbol: functionSymbol,
                        name: componentName,
                        module: module,
                        sema: sema,
                        signature: signature,
                        params: [selfParam],
                        body: body
                    )
                    continue
                }
            }

            let nullOutThrown = module.arena.appendExpr(.null, type: sema.types.nullableAnyType)
            body.append(.constValue(result: nullOutThrown, value: .null))
            body.append(.call(
                symbol: nil,
                callee: interner.intern("kk_abort_unreachable"),
                arguments: [nullOutThrown],
                result: resultExpr,
                canThrow: false,
                thrownResult: nil
            ))
            body.append(.returnValue(resultExpr))

            appendSyntheticFunctionWithSymbol(
                functionSymbol: functionSymbol,
                name: componentName,
                module: module,
                sema: sema,
                signature: signature,
                params: [selfParam],
                body: body
            )
        }
    }

    private func syntheticDataClassComponentSymbols(
        owner: SemanticSymbol,
        sema: SemaModule,
        interner: StringInterner
    ) -> [(index: Int, symbolID: SymbolID, signature: FunctionSignature)] {
        sema.symbols.children(ofFQName: owner.fqName)
            .compactMap { childID -> (Int, SymbolID, FunctionSignature)? in
                guard let sym = sema.symbols.symbol(childID),
                      sym.kind == .function,
                      sym.flags.contains(.synthetic),
                      let signature = sema.symbols.functionSignature(for: childID),
                      signature.parameterTypes.isEmpty
                else {
                    return nil
                }

                let name = interner.resolve(sym.name)
                guard name.hasPrefix("component"),
                      let index = Int(name.dropFirst("component".count)),
                      index >= 1
                else {
                    return nil
                }

                return (index, childID, signature)
            }
            .sorted { lhs, rhs in
                if lhs.0 == rhs.0 {
                    return lhs.1.rawValue < rhs.1.rawValue
                }
                return lhs.0 < rhs.0
            }
    }

    func primaryConstructorPropertySymbols(
        owner: SemanticSymbol,
        sema: SemaModule
    ) -> [SemanticSymbol?] {
        let childProperties = sema.symbols.children(ofFQName: owner.fqName)
            .compactMap { childID -> SemanticSymbol? in
                guard let symbol = sema.symbols.symbol(childID), symbol.kind == .property else {
                    return nil
                }
                return symbol
            }
        let propertiesByName = Dictionary(uniqueKeysWithValues: childProperties.map { ($0.name, $0) })

        guard let primaryCtorSymbol = sema.symbols.children(ofFQName: owner.fqName)
            .compactMap({ childID -> SymbolID? in
                guard let symbol = sema.symbols.symbol(childID),
                      symbol.kind == .constructor,
                      symbol.declSite == owner.declSite
                else {
                    return nil
                }
                return childID
            })
            .first,
            let primaryCtorSignature = sema.symbols.functionSignature(for: primaryCtorSymbol)
        else {
            return []
        }

        return primaryCtorSignature.valueParameterSymbols.map { paramSymbol in
            guard let param = sema.symbols.symbol(paramSymbol) else {
                return nil
            }
            return propertiesByName[param.name]
        }
    }

    private func enumEntrySymbols(owner: SemanticSymbol, symbols: SymbolTable) -> [SemanticSymbol] {
        symbols.children(ofFQName: owner.fqName)
            .compactMap { symbols.symbol($0) }
            .filter { $0.kind == .field }
            .sorted(by: {
                // Sort by source declaration offset first (Kotlin guarantees
                // enum entry order matches declaration order).  Fall back to
                // symbol ID which is monotonically assigned in parse order.
                let lhsOffset = $0.declSite?.start.offset ?? Int.max
                let rhsOffset = $1.declSite?.start.offset ?? Int.max
                if lhsOffset != rhsOffset {
                    return lhsOffset < rhsOffset
                }
                return $0.id.rawValue < $1.id.rawValue
            })
    }

    private func appendSyntheticCountFunctionIfNeeded(
        name: InternedString,
        owner: SemanticSymbol,
        value: Int64,
        returnType: TypeID,
        module: KIRModule,
        sema: SemaModule,
        existingFunctionSymbols: Set<SymbolID>
    ) {
        let signature = FunctionSignature(parameterTypes: [], returnType: returnType, isSuspend: false)
        let resultExpr = module.arena.appendExpr(
            .temporary(Int32(module.arena.expressions.count)),
            type: returnType
        )
        let body: [KIRInstruction] = [
            .constValue(result: resultExpr, value: .intLiteral(value)),
            .returnValue(resultExpr),
        ]
        appendSyntheticFunctionIfNeeded(
            name: name,
            owner: owner,
            module: module,
            sema: sema,
            signature: signature,
            params: [],
            body: body,
            existingFunctionSymbols: existingFunctionSymbols
        )
    }

    private func appendSyntheticStringFunctionIfNeeded(
        name: InternedString,
        owner: SemanticSymbol,
        value: InternedString,
        returnType: TypeID,
        module: KIRModule,
        sema: SemaModule,
        existingFunctionSymbols: Set<SymbolID>
    ) {
        let signature = FunctionSignature(parameterTypes: [], returnType: returnType, isSuspend: false)
        let resultExpr = module.arena.appendExpr(
            .temporary(Int32(module.arena.expressions.count)),
            type: returnType
        )
        let body: [KIRInstruction] = [
            .constValue(result: resultExpr, value: .stringLiteral(value)),
            .returnValue(resultExpr),
        ]
        appendSyntheticFunctionIfNeeded(
            name: name,
            owner: owner,
            module: module,
            sema: sema,
            signature: signature,
            params: [],
            body: body,
            existingFunctionSymbols: existingFunctionSymbols
        )
    }

    /// Synthesizes `values()` which returns an `Array<T>` containing all
    func appendSyntheticFunctionWithSymbol(
        functionSymbol: SymbolID,
        name: InternedString,
        module: KIRModule,
        sema: SemaModule,
        signature: FunctionSignature,
        params: [KIRParameter],
        body: [KIRInstruction]
    ) {
        sema.symbols.setFunctionSignature(signature, for: functionSymbol)
        _ = module.arena.appendDecl(.function(
            KIRFunction(
                symbol: functionSymbol,
                name: name,
                params: params,
                returnType: signature.returnType,
                body: body,
                isSuspend: false,
                isInline: false
            )
        ))
    }

    func appendSyntheticFunctionIfNeeded(
        name: InternedString,
        owner: SemanticSymbol,
        module: KIRModule,
        sema: SemaModule,
        signature: FunctionSignature,
        params: [KIRParameter],
        body: [KIRInstruction],
        existingFunctionSymbols: Set<SymbolID>
    ) {
        let fqName = owner.fqName + [name]
        let nonSyntheticConflict = sema.symbols.lookupAll(fqName: fqName).contains { symbolID in
            guard let symbol = sema.symbols.symbol(symbolID) else {
                return false
            }
            return symbol.kind == .function && !symbol.flags.contains(.synthetic)
        }
        if nonSyntheticConflict {
            return
        }

        let functionSymbol = sema.symbols.define(
            kind: .function,
            name: name,
            fqName: fqName,
            declSite: owner.declSite,
            visibility: .public,
            flags: [.synthetic, .static]
        )
        if existingFunctionSymbols.contains(functionSymbol) {
            return
        }
        sema.symbols.setFunctionSignature(
            FunctionSignature(
                receiverType: signature.receiverType,
                parameterTypes: signature.parameterTypes,
                returnType: signature.returnType,
                isSuspend: signature.isSuspend,
                valueParameterSymbols: params.map(\.symbol),
                valueParameterHasDefaultValues: signature.valueParameterHasDefaultValues.isEmpty
                    ? params.map { _ in false }
                    : signature.valueParameterHasDefaultValues,
                valueParameterIsVararg: signature.valueParameterIsVararg.isEmpty
                    ? params.map { _ in false }
                    : signature.valueParameterIsVararg,
                typeParameterSymbols: []
            ),
            for: functionSymbol
        )
        _ = module.arena.appendDecl(.function(
            KIRFunction(
                symbol: functionSymbol,
                name: name,
                params: params,
                returnType: signature.returnType,
                body: body,
                isSuspend: false,
                isInline: false
            )
        ))
    }
}
