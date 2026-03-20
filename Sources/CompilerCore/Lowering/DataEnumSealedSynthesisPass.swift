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
        rewriteSyntheticEnumEntryRefs(module: module, sema: sema, interner: ctx.interner)

        module.recordLowering(Self.name)
    }

    /// Replaces `constValue(result: r, value: .symbolRef(sym))` where `sym`
    /// is a synthetic field owned by a synthetic enum class with
    /// `constValue(result: r, value: .intLiteral(ordinal))` followed by a
    /// `call kk_box_int` so the value is a boxed enum ordinal.
    private func rewriteSyntheticEnumEntryRefs(
        module: KIRModule,
        sema: SemaModule,
        interner: StringInterner
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
        appendSyntheticDataCopyIfNeeded(
            name: ctx.interner.intern("\(ctx.interner.resolve(nominalSymbol.name))$copy"),
            owner: nominalSymbol, module: module, sema: sema,
            existingFunctionSymbols: existingFunctionSymbols, interner: ctx.interner
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

    private func anyToStringTag(for type: TypeID, sema: SemaModule) -> Int64 {
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

    private func primaryConstructorPropertySymbols(
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
            .sorted(by: { $0.id.rawValue < $1.id.rawValue })
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

    private func appendSyntheticDataCopyIfNeeded(
        name: InternedString,
        owner: SemanticSymbol,
        module: KIRModule,
        sema: SemaModule,
        existingFunctionSymbols: Set<SymbolID>,
        interner: StringInterner
    ) {
        guard owner.kind == .class || owner.kind == .enumClass || owner.kind == .object else {
            return
        }

        let receiverType = sema.types.make(.classType(ClassType(
            classSymbol: owner.id,
            args: [],
            nullability: .nonNull
        )))
        let selfParamName = interner.intern("$self")
        let fqName = owner.fqName + [name]
        let selfParamSymbol = sema.symbols.define(
            kind: .valueParameter,
            name: selfParamName,
            fqName: fqName + [selfParamName],
            declSite: owner.declSite,
            visibility: .private,
            flags: [.synthetic]
        )
        let selfParam = KIRParameter(symbol: selfParamSymbol, type: receiverType)

        // Look up the primary constructor to get property parameter types.
        let initName = interner.intern("<init>")
        let ctorFQName = owner.fqName + [initName]
        let ctorSymbol = sema.symbols.lookupAll(fqName: ctorFQName).first { symbolID in
            sema.symbols.symbol(symbolID)?.kind == .constructor
        }

        // Guard: if no constructor is found, emit a simple self-returning copy()
        // to avoid generating an invalid .call instruction with nil symbol.
        guard let resolvedCtorSymbol = ctorSymbol,
              let ctorSignature = sema.symbols.functionSignature(for: resolvedCtorSymbol)
        else {
            let resultExpr = module.arena.appendExpr(
                .temporary(Int32(module.arena.expressions.count)),
                type: receiverType
            )
            let body: [KIRInstruction] = [
                .constValue(result: resultExpr, value: .symbolRef(selfParamSymbol)),
                .returnValue(resultExpr),
            ]
            let signature = FunctionSignature(
                parameterTypes: [receiverType],
                returnType: receiverType,
                isSuspend: false,
                valueParameterSymbols: [selfParamSymbol],
                valueParameterHasDefaultValues: [false],
                valueParameterIsVararg: [false]
            )
            appendSyntheticFunctionIfNeeded(
                name: name,
                owner: owner,
                module: module,
                sema: sema,
                signature: signature,
                params: [selfParam],
                body: body,
                existingFunctionSymbols: existingFunctionSymbols
            )
            return
        }

        // Collect constructor value parameters (excluding receiver).
        // The constructor signature stores symbols in valueParameterSymbols and
        // types in parameterTypes. When a receiver type is prepended to
        // parameterTypes (but not to valueParameterSymbols), we strip the leading
        // receiver entry from parameterTypes so that both arrays align 1-to-1.
        let ctorParamSymbols = ctorSignature.valueParameterSymbols
        var ctorParamTypes = ctorSignature.parameterTypes
        if ctorParamTypes.count > ctorParamSymbols.count,
           ctorParamTypes.first == receiverType {
            ctorParamTypes.removeFirst()
        }

        // Pair up symbols and types, truncating to the shorter array for safety.
        let pairCount = min(ctorParamSymbols.count, ctorParamTypes.count)
        let propertyParams: [(symbol: SymbolID, type: TypeID)] = (0..<pairCount).map { i in
            (ctorParamSymbols[i], ctorParamTypes[i])
        }

        // Build KIR parameters and body for copy().
        // Each copy parameter mirrors the corresponding constructor parameter name
        // (e.g. name, age) so diagnostics and dumps reflect Kotlin's copy(name=..., age=...).
        var allParams: [KIRParameter] = [selfParam]
        var allParamSymbols: [SymbolID] = [selfParamSymbol]
        var allParamTypes: [TypeID] = [receiverType]
        var allParamHasDefault: [Bool] = [false]
        var allParamIsVararg: [Bool] = [false]
        var copyParamSymbols: [SymbolID] = []

        for (ctorSym, paramType) in propertyParams {
            // Reuse the constructor parameter's name for the copy() parameter.
            let ctorParamName = sema.symbols.symbol(ctorSym)?.name ?? interner.intern("$copy_\(allParams.count)")
            let paramSymbol = sema.symbols.define(
                kind: .valueParameter,
                name: ctorParamName,
                fqName: fqName + [ctorParamName],
                declSite: owner.declSite,
                visibility: .private,
                flags: [.synthetic]
            )
            allParams.append(KIRParameter(symbol: paramSymbol, type: paramType))
            allParamSymbols.append(paramSymbol)
            allParamTypes.append(paramType)
            allParamHasDefault.append(true)
            allParamIsVararg.append(false)
            copyParamSymbols.append(paramSymbol)
        }

        var body: [KIRInstruction] = []

        // Load each copy parameter.
        var ctorArgExprs: [KIRExprID] = []
        for (index, paramSymbol) in copyParamSymbols.enumerated() {
            let paramType = propertyParams[index].type
            let paramExpr = module.arena.appendExpr(
                .temporary(Int32(module.arena.expressions.count)),
                type: paramType
            )
            body.append(.constValue(result: paramExpr, value: .symbolRef(paramSymbol)))
            ctorArgExprs.append(paramExpr)
        }

        // Call the constructor with the (possibly overridden) parameters.
        let resultExpr = module.arena.appendExpr(
            .temporary(Int32(module.arena.expressions.count)),
            type: receiverType
        )
        body.append(.call(
            symbol: resolvedCtorSymbol,
            callee: initName,
            arguments: ctorArgExprs,
            result: resultExpr,
            canThrow: false,
            thrownResult: nil
        ))
        body.append(.returnValue(resultExpr))

        let signature = FunctionSignature(
            parameterTypes: allParamTypes,
            returnType: receiverType,
            isSuspend: false,
            valueParameterSymbols: allParamSymbols,
            valueParameterHasDefaultValues: allParamHasDefault,
            valueParameterIsVararg: allParamIsVararg
        )
        appendSyntheticFunctionIfNeeded(
            name: name,
            owner: owner,
            module: module,
            sema: sema,
            signature: signature,
            params: allParams,
            body: body,
            existingFunctionSymbols: existingFunctionSymbols
        )
    }

    /// Synthesizes `toString(): String` for data object, returning the object name.
    /// Uses existingSymbol when provided (from Sema) so call resolution matches the KIR function.
    private func appendSyntheticDataObjectToStringIfNeeded(
        name: InternedString,
        owner: SemanticSymbol,
        objectName: InternedString,
        existingSymbol: SymbolID?,
        module: KIRModule,
        sema: SemaModule,
        existingFunctionSymbols: Set<SymbolID>,
        interner: StringInterner
    ) {
        guard owner.kind == .object, let functionSymbol = existingSymbol else {
            return
        }
        if existingFunctionSymbols.contains(functionSymbol) {
            return
        }

        let receiverType = sema.types.make(.classType(ClassType(
            classSymbol: owner.id,
            args: [],
            nullability: .nonNull
        )))
        let stringType = sema.types.make(.primitive(.string, .nonNull))
        let parameterName = interner.intern("$self")
        let fqName = owner.fqName + [name]
        let parameterSymbol = sema.symbols.define(
            kind: .valueParameter,
            name: parameterName,
            fqName: fqName + [parameterName],
            declSite: owner.declSite,
            visibility: .private,
            flags: [.synthetic]
        )
        let parameter = KIRParameter(symbol: parameterSymbol, type: receiverType)
        let resultExpr = module.arena.appendExpr(
            .temporary(Int32(module.arena.expressions.count)),
            type: stringType
        )
        let body: [KIRInstruction] = [
            .constValue(result: resultExpr, value: .stringLiteral(objectName)),
            .returnValue(resultExpr),
        ]
        let signature = FunctionSignature(
            receiverType: receiverType,
            parameterTypes: [],
            returnType: stringType,
            isSuspend: false,
            valueParameterSymbols: [],
            valueParameterHasDefaultValues: [],
            valueParameterIsVararg: [],
            typeParameterSymbols: []
        )
        appendSyntheticFunctionWithSymbol(
            functionSymbol: functionSymbol,
            name: name,
            module: module,
            sema: sema,
            signature: signature,
            params: [parameter],
            body: body
        )
    }

    /// Synthesizes `equals(other: Any?): Boolean` for data object (identity comparison via kk_op_eq).
    private func appendSyntheticDataObjectEqualsIfNeeded(
        owner: SemanticSymbol,
        existingSymbol: SymbolID?,
        module: KIRModule,
        sema: SemaModule,
        existingFunctionSymbols: Set<SymbolID>,
        interner: StringInterner
    ) {
        guard owner.kind == .object, let functionSymbol = existingSymbol else {
            return
        }
        if existingFunctionSymbols.contains(functionSymbol) {
            return
        }

        let receiverType = sema.types.make(.classType(ClassType(
            classSymbol: owner.id,
            args: [],
            nullability: .nonNull
        )))
        let boolType = sema.types.make(.primitive(.boolean, .nonNull))
        let nullableAnyType = sema.types.nullableAnyType
        let equalsName = interner.intern("equals")
        let paramName = interner.intern("other")
        let fqName = owner.fqName + [equalsName]
        let paramSymbol = sema.symbols.define(
            kind: .valueParameter,
            name: paramName,
            fqName: fqName + [paramName],
            declSite: owner.declSite,
            visibility: .private,
            flags: [.synthetic]
        )
        let receiverParam = KIRParameter(
            symbol: sema.symbols.define(
                kind: .valueParameter,
                name: interner.intern("$self"),
                fqName: fqName + [interner.intern("$self")],
                declSite: owner.declSite,
                visibility: .private,
                flags: [.synthetic]
            ),
            type: receiverType
        )
        let otherParam = KIRParameter(symbol: paramSymbol, type: nullableAnyType)
        let receiverRef = module.arena.appendExpr(.symbolRef(receiverParam.symbol), type: receiverType)
        let otherRef = module.arena.appendExpr(.symbolRef(paramSymbol), type: nullableAnyType)
        let resultExpr = module.arena.appendExpr(
            .temporary(Int32(module.arena.expressions.count)),
            type: boolType
        )
        let body: [KIRInstruction] = [
            .constValue(result: receiverRef, value: .symbolRef(receiverParam.symbol)),
            .constValue(result: otherRef, value: .symbolRef(paramSymbol)),
            .call(
                symbol: nil,
                callee: interner.intern("kk_op_eq"),
                arguments: [receiverRef, otherRef],
                result: resultExpr,
                canThrow: false,
                thrownResult: nil
            ),
            .returnValue(resultExpr),
        ]
        let signature = FunctionSignature(
            receiverType: receiverType,
            parameterTypes: [nullableAnyType],
            returnType: boolType,
            isSuspend: false,
            valueParameterSymbols: [paramSymbol],
            valueParameterHasDefaultValues: [false],
            valueParameterIsVararg: [false],
            typeParameterSymbols: []
        )
        appendSyntheticFunctionWithSymbol(
            functionSymbol: functionSymbol,
            name: equalsName,
            module: module,
            sema: sema,
            signature: signature,
            params: [receiverParam, otherParam],
            body: body
        )
    }

    /// Synthesizes `hashCode(): Int` for data class.
    /// Computes hash from all constructor properties using the standard Kotlin algorithm:
    ///   var result = property1.hashCode()
    ///   result = 31 * result + property2.hashCode()
    ///   ...
    ///   return result
    /// Each property hash is obtained via `kk_any_hashCode`, and the accumulation
    /// uses `kk_op_mul` (31 * result) and `kk_op_add` (+ propertyHash).
    private func appendSyntheticDataClassHashCodeIfNeeded(
        owner: SemanticSymbol,
        existingSymbol: SymbolID?,
        module: KIRModule,
        sema: SemaModule,
        existingFunctionSymbols: Set<SymbolID>,
        interner: StringInterner
    ) {
        guard owner.kind == .class, let functionSymbol = existingSymbol else {
            return
        }
        if existingFunctionSymbols.contains(functionSymbol) {
            return
        }

        let receiverType = sema.types.make(.classType(ClassType(
            classSymbol: owner.id,
            args: [],
            nullability: .nonNull
        )))
        let intType = sema.types.make(.primitive(.int, .nonNull))
        let hashCodeName = interner.intern("hashCode")
        let fqName = owner.fqName + [hashCodeName]

        let receiverParamSymbol = sema.symbols.define(
            kind: .valueParameter,
            name: interner.intern("$self"),
            fqName: fqName + [interner.intern("$self")],
            declSite: owner.declSite,
            visibility: .private,
            flags: [.synthetic]
        )
        let receiverParam = KIRParameter(symbol: receiverParamSymbol, type: receiverType)

        let propertySymbols = sema.symbols.children(ofFQName: owner.fqName)
            .compactMap { sema.symbols.symbol($0) }
            .filter { $0.kind == .property }
            .sorted(by: { $0.id.rawValue < $1.id.rawValue })

        var body: [KIRInstruction] = []

        let receiverRef = module.arena.appendExpr(.symbolRef(receiverParamSymbol), type: receiverType)
        body.append(.constValue(result: receiverRef, value: .symbolRef(receiverParamSymbol)))

        let hashCodeCallee = interner.intern("kk_any_hashCode")
        let mulCallee = interner.intern("kk_op_mul")
        let addCallee = interner.intern("kk_op_add")

        if propertySymbols.isEmpty {
            let zeroExpr = module.arena.appendExpr(
                .temporary(Int32(module.arena.expressions.count)),
                type: intType
            )
            body.append(.constValue(result: zeroExpr, value: .intLiteral(0)))
            body.append(.returnValue(zeroExpr))
        } else {
            var resultExpr: KIRExprID!
            for (index, propSym) in propertySymbols.enumerated() {
                let fieldOffsetValue: Int64
                if let layout = sema.symbols.nominalLayout(for: owner.id),
                   let offset = layout.fieldOffsets[propSym.id] {
                    fieldOffsetValue = Int64(offset)
                } else {
                    fieldOffsetValue = Int64(index)
                }

                let fieldOffsetExpr = module.arena.appendExpr(
                    .temporary(Int32(module.arena.expressions.count)),
                    type: intType
                )
                body.append(.constValue(result: fieldOffsetExpr, value: .intLiteral(fieldOffsetValue)))

                let propHashExpr = module.arena.appendExpr(
                    .temporary(Int32(module.arena.expressions.count)),
                    type: intType
                )
                body.append(.call(
                    symbol: nil,
                    callee: hashCodeCallee,
                    arguments: [receiverRef, fieldOffsetExpr],
                    result: propHashExpr,
                    canThrow: false,
                    thrownResult: nil
                ))

                if index == 0 {
                    resultExpr = propHashExpr
                } else {
                    let thirtyOneExpr = module.arena.appendExpr(
                        .temporary(Int32(module.arena.expressions.count)),
                        type: intType
                    )
                    body.append(.constValue(result: thirtyOneExpr, value: .intLiteral(31)))

                    let mulExpr = module.arena.appendExpr(
                        .temporary(Int32(module.arena.expressions.count)),
                        type: intType
                    )
                    body.append(.call(
                        symbol: nil,
                        callee: mulCallee,
                        arguments: [thirtyOneExpr, resultExpr],
                        result: mulExpr,
                        canThrow: false,
                        thrownResult: nil
                    ))

                    let addExpr = module.arena.appendExpr(
                        .temporary(Int32(module.arena.expressions.count)),
                        type: intType
                    )
                    body.append(.call(
                        symbol: nil,
                        callee: addCallee,
                        arguments: [mulExpr, propHashExpr],
                        result: addExpr,
                        canThrow: false,
                        thrownResult: nil
                    ))

                    resultExpr = addExpr
                }
            }
            body.append(.returnValue(resultExpr))
        }

        let signature = FunctionSignature(
            receiverType: receiverType,
            parameterTypes: [],
            returnType: intType,
            isSuspend: false,
            valueParameterSymbols: [],
            valueParameterHasDefaultValues: [],
            valueParameterIsVararg: [],
            typeParameterSymbols: []
        )
        appendSyntheticFunctionWithSymbol(
            functionSymbol: functionSymbol,
            name: hashCodeName,
            module: module,
            sema: sema,
            signature: signature,
            params: [receiverParam],
            body: body
        )
    }

    /// Synthesizes `toString(): String` for data class with properties.
    /// Output format: "ClassName(prop1=val1, prop2=val2)"
    /// Each property value is converted to string via `kk_any_to_string` and concatenated.
    private func appendSyntheticDataClassToStringIfNeeded(
        name: InternedString,
        owner: SemanticSymbol,
        properties: [SemanticSymbol],
        existingSymbol: SymbolID?,
        module: KIRModule,
        sema: SemaModule,
        existingFunctionSymbols: Set<SymbolID>,
        interner: StringInterner
    ) {
        guard owner.kind == .class, let functionSymbol = existingSymbol else {
            return
        }
        if existingFunctionSymbols.contains(functionSymbol) {
            return
        }

        let receiverType = sema.types.make(.classType(ClassType(
            classSymbol: owner.id,
            args: [],
            nullability: .nonNull
        )))
        let stringType = sema.types.make(.primitive(.string, .nonNull))
        let intType = sema.types.make(.primitive(.int, .nonNull))
        let fqName = owner.fqName + [name]
        let parameterName = interner.intern("$self")
        let parameterSymbol = sema.symbols.define(
            kind: .valueParameter,
            name: parameterName,
            fqName: fqName + [parameterName],
            declSite: owner.declSite,
            visibility: .private,
            flags: [.synthetic]
        )
        let parameter = KIRParameter(symbol: parameterSymbol, type: receiverType)

        var body: [KIRInstruction] = []

        // Start with "ClassName("
        let className = interner.resolve(owner.name)
        let prefixStr = interner.intern("\(className)(")
        let prefixExpr = module.arena.appendExpr(
            .temporary(Int32(module.arena.expressions.count)),
            type: stringType
        )
        body.append(.constValue(result: prefixExpr, value: .stringLiteral(prefixStr)))
        let builderType = sema.types.anyType
        let builderExpr = module.arena.appendExpr(
            .temporary(Int32(module.arena.expressions.count)),
            type: builderType
        )
        body.append(.call(
            symbol: nil,
            callee: interner.intern("kk_string_builder_new_from_string"),
            arguments: [prefixExpr],
            result: builderExpr,
            canThrow: false,
            thrownResult: nil
        ))

        for (index, property) in properties.enumerated() {
            let propName = interner.resolve(property.name)
            // Append "propName=" (or ", propName=" for subsequent properties)
            let labelStr: String = index == 0 ? "\(propName)=" : ", \(propName)="
            let labelInterned = interner.intern(labelStr)
            let labelExpr = module.arena.appendExpr(
                .temporary(Int32(module.arena.expressions.count)),
                type: stringType
            )
            body.append(.constValue(result: labelExpr, value: .stringLiteral(labelInterned)))

            body.append(.call(
                symbol: nil,
                callee: interner.intern("kk_string_builder_append_obj"),
                arguments: [builderExpr, labelExpr],
                result: builderExpr,
                canThrow: false,
                thrownResult: nil
            ))

            // Load property value via getter call: <ClassName>.<propName>$get(self)
            let receiverRef = module.arena.appendExpr(.symbolRef(parameterSymbol), type: receiverType)
            body.append(.constValue(result: receiverRef, value: .symbolRef(parameterSymbol)))

            let propType = sema.symbols.propertyType(for: property.id) ?? sema.types.anyType
            let propValue = module.arena.appendExpr(
                .temporary(Int32(module.arena.expressions.count)),
                type: propType
            )
            let getterName = interner.intern("\(propName)$get")
            body.append(.call(
                symbol: nil,
                callee: getterName,
                arguments: [receiverRef],
                result: propValue,
                canThrow: false,
                thrownResult: nil
            ))

            // Convert to string via kk_any_to_string using the same tag convention
            // as Any.toString lowering.
            let anyTag = anyToStringTag(for: propType, sema: sema)
            let tagExpr = module.arena.appendExpr(
                .temporary(Int32(module.arena.expressions.count)),
                type: intType
            )
            body.append(.constValue(result: tagExpr, value: .intLiteral(anyTag)))

            let propStr = module.arena.appendExpr(
                .temporary(Int32(module.arena.expressions.count)),
                type: stringType
            )
            body.append(.call(
                symbol: nil,
                callee: interner.intern("kk_any_to_string"),
                arguments: [propValue, tagExpr],
                result: propStr,
                canThrow: false,
                thrownResult: nil
            ))

            body.append(.call(
                symbol: nil,
                callee: interner.intern("kk_string_builder_append_obj"),
                arguments: [builderExpr, propStr],
                result: builderExpr,
                canThrow: false,
                thrownResult: nil
            ))
        }

        // Append closing ")"
        let suffixStr = interner.intern(")")
        let suffixExpr = module.arena.appendExpr(
            .temporary(Int32(module.arena.expressions.count)),
            type: stringType
        )
        body.append(.constValue(result: suffixExpr, value: .stringLiteral(suffixStr)))

        body.append(.call(
            symbol: nil,
            callee: interner.intern("kk_string_builder_append_obj"),
            arguments: [builderExpr, suffixExpr],
            result: builderExpr,
            canThrow: false,
            thrownResult: nil
        ))

        let resultExpr = module.arena.appendExpr(
            .temporary(Int32(module.arena.expressions.count)),
            type: stringType
        )
        body.append(.call(
            symbol: nil,
            callee: interner.intern("kk_string_builder_toString"),
            arguments: [builderExpr],
            result: resultExpr,
            canThrow: false,
            thrownResult: nil
        ))
        body.append(.returnValue(resultExpr))

        let signature = FunctionSignature(
            receiverType: receiverType,
            parameterTypes: [],
            returnType: stringType,
            isSuspend: false,
            valueParameterSymbols: [],
            valueParameterHasDefaultValues: [],
            valueParameterIsVararg: [],
            typeParameterSymbols: []
        )
        appendSyntheticFunctionWithSymbol(
            functionSymbol: functionSymbol,
            name: name,
            module: module,
            sema: sema,
            signature: signature,
            params: [parameter],
            body: body
        )
    }

    /// Synthesizes `equals(other: Any?): Boolean` for data class with properties.
    /// Compares each property of `this` and `other` via `kk_op_eq`, returning false
    /// if any differ.
    private func appendSyntheticDataClassEqualsIfNeeded(
        owner: SemanticSymbol,
        properties: [SemanticSymbol],
        existingSymbol: SymbolID?,
        module: KIRModule,
        sema: SemaModule,
        existingFunctionSymbols: Set<SymbolID>,
        interner: StringInterner
    ) {
        guard owner.kind == .class, let functionSymbol = existingSymbol else {
            return
        }
        if existingFunctionSymbols.contains(functionSymbol) {
            return
        }

        let receiverType = sema.types.make(.classType(ClassType(
            classSymbol: owner.id,
            args: [],
            nullability: .nonNull
        )))
        let boolType = sema.types.make(.primitive(.boolean, .nonNull))
        let nullableAnyType = sema.types.nullableAnyType
        let equalsName = interner.intern("equals")
        let paramName = interner.intern("other")
        let fqName = owner.fqName + [equalsName]
        let paramSymbol = sema.symbols.define(
            kind: .valueParameter,
            name: paramName,
            fqName: fqName + [paramName],
            declSite: owner.declSite,
            visibility: .private,
            flags: [.synthetic]
        )
        let receiverParam = KIRParameter(
            symbol: sema.symbols.define(
                kind: .valueParameter,
                name: interner.intern("$self"),
                fqName: fqName + [interner.intern("$self")],
                declSite: owner.declSite,
                visibility: .private,
                flags: [.synthetic]
            ),
            type: receiverType
        )
        let otherParam = KIRParameter(symbol: paramSymbol, type: nullableAnyType)

        var body: [KIRInstruction] = []
        var nextLabel: Int32 = 0
        func allocateLabel() -> Int32 {
            defer { nextLabel += 1 }
            return nextLabel
        }

        if properties.isEmpty {
            let receiverRef = module.arena.appendExpr(.symbolRef(receiverParam.symbol), type: receiverType)
            let otherRef = module.arena.appendExpr(.symbolRef(paramSymbol), type: nullableAnyType)
            let resultExpr = module.arena.appendExpr(
                .temporary(Int32(module.arena.expressions.count)),
                type: boolType
            )
            body.append(.constValue(result: receiverRef, value: .symbolRef(receiverParam.symbol)))
            body.append(.constValue(result: otherRef, value: .symbolRef(paramSymbol)))
            body.append(.call(
                symbol: nil,
                callee: interner.intern("kk_op_eq"),
                arguments: [receiverRef, otherRef],
                result: resultExpr,
                canThrow: false,
                thrownResult: nil
            ))
            body.append(.returnValue(resultExpr))
        } else {
            let intType = sema.types.intType
            let falseExpr = module.arena.appendExpr(.boolLiteral(false), type: boolType)
            body.append(.constValue(result: falseExpr, value: .boolLiteral(false)))

            let typeTokenValue = RuntimeTypeCheckToken.encode(type: receiverType, sema: sema, interner: interner)
            let typeTokenExpr = module.arena.appendExpr(.intLiteral(typeTokenValue), type: intType)
            body.append(.constValue(result: typeTokenExpr, value: .intLiteral(typeTokenValue)))

            let otherAnyRef = module.arena.appendExpr(.symbolRef(paramSymbol), type: nullableAnyType)
            body.append(.constValue(result: otherAnyRef, value: .symbolRef(paramSymbol)))

            let isSameTypeExpr = module.arena.appendExpr(
                .temporary(Int32(module.arena.expressions.count)),
                type: boolType
            )
            body.append(.call(
                symbol: nil,
                callee: interner.intern("kk_op_is"),
                arguments: [otherAnyRef, typeTokenExpr],
                result: isSameTypeExpr,
                canThrow: false,
                thrownResult: nil
            ))

            let returnFalseLabel = allocateLabel()
            body.append(.jumpIfEqual(lhs: isSameTypeExpr, rhs: falseExpr, target: returnFalseLabel))

            let otherTypedRef = module.arena.appendExpr(
                .temporary(Int32(module.arena.expressions.count)),
                type: receiverType
            )
            body.append(.call(
                symbol: nil,
                callee: interner.intern("kk_op_safe_cast"),
                arguments: [otherAnyRef, typeTokenExpr],
                result: otherTypedRef,
                canThrow: false,
                thrownResult: nil
            ))

            for property in properties {
                let propName = interner.resolve(property.name)
                let getterName = interner.intern("\(propName)$get")
                let propType = sema.symbols.propertyType(for: property.id) ?? sema.types.anyType

                let selfRef = module.arena.appendExpr(.symbolRef(receiverParam.symbol), type: receiverType)
                body.append(.constValue(result: selfRef, value: .symbolRef(receiverParam.symbol)))
                let selfProp = module.arena.appendExpr(
                    .temporary(Int32(module.arena.expressions.count)),
                    type: propType
                )
                body.append(.call(
                    symbol: nil,
                    callee: getterName,
                    arguments: [selfRef],
                    result: selfProp,
                    canThrow: false,
                    thrownResult: nil
                ))

                let otherProp = module.arena.appendExpr(
                    .temporary(Int32(module.arena.expressions.count)),
                    type: propType
                )
                body.append(.call(
                    symbol: nil,
                    callee: getterName,
                    arguments: [otherTypedRef],
                    result: otherProp,
                    canThrow: false,
                    thrownResult: nil
                ))

                let cmpResult = module.arena.appendExpr(
                    .temporary(Int32(module.arena.expressions.count)),
                    type: boolType
                )
                body.append(.call(
                    symbol: nil,
                    callee: interner.intern("kk_op_eq"),
                    arguments: [selfProp, otherProp],
                    result: cmpResult,
                    canThrow: false,
                    thrownResult: nil
                ))

                body.append(.jumpIfEqual(lhs: cmpResult, rhs: falseExpr, target: returnFalseLabel))
            }

            let trueResult = module.arena.appendExpr(
                .boolLiteral(true),
                type: boolType
            )
            body.append(.constValue(result: trueResult, value: .boolLiteral(true)))
            body.append(.returnValue(trueResult))

            body.append(.label(returnFalseLabel))
            let falseResult = module.arena.appendExpr(
                .boolLiteral(false),
                type: boolType
            )
            body.append(.constValue(result: falseResult, value: .boolLiteral(false)))
            body.append(.returnValue(falseResult))
        }

        let signature = FunctionSignature(
            receiverType: receiverType,
            parameterTypes: [nullableAnyType],
            returnType: boolType,
            isSuspend: false,
            valueParameterSymbols: [paramSymbol],
            valueParameterHasDefaultValues: [false],
            valueParameterIsVararg: [false],
            typeParameterSymbols: []
        )
        appendSyntheticFunctionWithSymbol(
            functionSymbol: functionSymbol,
            name: equalsName,
            module: module,
            sema: sema,
            signature: signature,
            params: [receiverParam, otherParam],
            body: body
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
    /// enum entry singletons.
    /// The body is: kk_array_new(count) -> kk_array_set for each entry -> kk_enum_make_values_array.
    private func appendSyntheticEnumValuesIfNeeded(
        name: InternedString,
        owner: SemanticSymbol,
        entries: [SemanticSymbol],
        module: KIRModule,
        sema: SemaModule,
        existingFunctionSymbols: Set<SymbolID>,
        interner: StringInterner
    ) {
        let intType = sema.types.make(.primitive(.int, .nonNull))

        // Compute the enum entry type from the owner symbol
        let entryType = sema.types.make(.classType(ClassType(
            classSymbol: owner.id,
            args: [],
            nullability: .nonNull
        )))
        // values() returns Array<T>, represented as anyType at the erased level
        let returnType = sema.types.anyType

        let signature = FunctionSignature(parameterTypes: [], returnType: returnType, isSuspend: false)

        var body: [KIRInstruction] = []

        // count constant
        let countExpr = module.arena.appendExpr(
            .temporary(Int32(module.arena.expressions.count)), type: intType
        )
        body.append(.constValue(result: countExpr, value: .intLiteral(Int64(entries.count))))

        // kk_array_new(count) -- intermediate array uses anyType
        let arrayExpr = module.arena.appendExpr(
            .temporary(Int32(module.arena.expressions.count)), type: sema.types.anyType
        )
        body.append(.call(
            symbol: nil,
            callee: interner.intern("kk_array_new"),
            arguments: [countExpr],
            result: arrayExpr,
            canThrow: false,
            thrownResult: nil
        ))

        // Enum values are represented by their ordinal payloads at runtime, so
        // populate the array directly with ordinal literals rather than reading
        // enum globals that may not have been static-initialized yet.
        for (ordinal, _) in entries.enumerated() {
            let indexExpr = module.arena.appendExpr(
                .temporary(Int32(module.arena.expressions.count)), type: intType
            )
            body.append(.constValue(result: indexExpr, value: .intLiteral(Int64(ordinal))))

            let entryRef = module.arena.appendExpr(
                .temporary(Int32(module.arena.expressions.count)), type: entryType
            )
            body.append(.constValue(result: entryRef, value: .intLiteral(Int64(ordinal))))

            body.append(.call(
                symbol: nil,
                callee: interner.intern("kk_array_set"),
                arguments: [arrayExpr, indexExpr, entryRef],
                result: nil,
                canThrow: false,
                thrownResult: nil
            ))
        }

        // kk_enum_make_values_array(array, count) -- result uses the enum type
        let listExpr = module.arena.appendExpr(
            .temporary(Int32(module.arena.expressions.count)), type: returnType
        )
        body.append(.call(
            symbol: nil,
            callee: interner.intern("kk_enum_make_values_array"),
            arguments: [arrayExpr, countExpr],
            result: listExpr,
            canThrow: false,
            thrownResult: nil
        ))

        body.append(.returnValue(listExpr))

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

    /// Synthesizes the `entries` getter on the companion object.
    /// `Color.entries` returns a List containing all enum entry singletons.
    /// The body is: kk_array_new(count) → kk_array_set for each entry → kk_enum_make_values_array.
    private func appendSyntheticEnumEntriesGetterIfNeeded(
        owner: SemanticSymbol,
        enumSymbol: SemanticSymbol,
        entries: [SemanticSymbol],
        module: KIRModule,
        sema: SemaModule,
        existingFunctionSymbols: Set<SymbolID>,
        interner: StringInterner
    ) {
        let intType = sema.types.make(.primitive(.int, .nonNull))
        let getterName = interner.intern("entries$get")

        // Compute correct types from enumSymbol, matching CallLowerer+EnumStdlib pattern
        let entryType = sema.types.make(.classType(ClassType(
            classSymbol: enumSymbol.id,
            args: [],
            nullability: .nonNull
        )))
        // entries getter returns Array<T>, represented as anyType at the erased level
        let returnType = sema.types.anyType

        let signature = FunctionSignature(parameterTypes: [], returnType: returnType, isSuspend: false)

        var body: [KIRInstruction] = []

        // count constant
        let countExpr = module.arena.appendExpr(
            .temporary(Int32(module.arena.expressions.count)), type: intType
        )
        body.append(.constValue(result: countExpr, value: .intLiteral(Int64(entries.count))))

        // kk_array_new(count) -- intermediate array uses anyType
        let arrayExpr = module.arena.appendExpr(
            .temporary(Int32(module.arena.expressions.count)), type: sema.types.anyType
        )
        body.append(.call(
            symbol: nil,
            callee: interner.intern("kk_array_new"),
            arguments: [countExpr],
            result: arrayExpr,
            canThrow: false,
            thrownResult: nil
        ))

        // Enum values are represented by their ordinal payloads at runtime, so
        // populate the array directly with ordinal literals rather than reading
        // enum globals that may not have been static-initialized yet.
        for (ordinal, _) in entries.enumerated() {
            let indexExpr = module.arena.appendExpr(
                .temporary(Int32(module.arena.expressions.count)), type: intType
            )
            body.append(.constValue(result: indexExpr, value: .intLiteral(Int64(ordinal))))

            let entryRef = module.arena.appendExpr(
                .temporary(Int32(module.arena.expressions.count)), type: entryType
            )
            body.append(.constValue(result: entryRef, value: .intLiteral(Int64(ordinal))))

            body.append(.call(
                symbol: nil,
                callee: interner.intern("kk_array_set"),
                arguments: [arrayExpr, indexExpr, entryRef],
                result: nil,
                canThrow: false,
                thrownResult: nil
            ))
        }

        // kk_enum_make_values_array(array, count) -- result uses the enum type
        let listExpr = module.arena.appendExpr(
            .temporary(Int32(module.arena.expressions.count)), type: returnType
        )
        body.append(.call(
            symbol: nil,
            callee: interner.intern("kk_enum_make_values_array"),
            arguments: [arrayExpr, countExpr],
            result: listExpr,
            canThrow: false,
            thrownResult: nil
        ))

        body.append(.returnValue(listExpr))

        appendSyntheticFunctionIfNeeded(
            name: getterName,
            owner: owner,
            module: module,
            sema: sema,
            signature: signature,
            params: [],
            body: body,
            existingFunctionSymbols: existingFunctionSymbols
        )
    }

    /// Synthesizes `$enumOrdinalToName(ordinal: Int): String` for (valueOf result).name.
    /// Switches on ordinal and returns the entry name via the per-entry $enumName helpers.
    private func appendSyntheticEnumOrdinalToNameIfNeeded(
        owner: SemanticSymbol,
        entries: [SemanticSymbol],
        module: KIRModule,
        sema: SemaModule,
        existingFunctionSymbols: Set<SymbolID>,
        interner: StringInterner
    ) {
        let intType = sema.types.make(.primitive(.int, .nonNull))
        let stringType = sema.types.make(.primitive(.string, .nonNull))
        let name = interner.intern("$enumOrdinalToName")
        let fqName = owner.fqName + [name]
        let paramName = interner.intern("$ordinal")
        let paramSymbol = sema.symbols.define(
            kind: .valueParameter,
            name: paramName,
            fqName: fqName + [paramName],
            declSite: owner.declSite,
            visibility: .private,
            flags: [.synthetic]
        )
        let param = KIRParameter(symbol: paramSymbol, type: intType)
        let paramRef = module.arena.appendExpr(.symbolRef(paramSymbol), type: intType)
        let unboxedOrdinalRef = module.arena.appendExpr(
            .temporary(Int32(module.arena.expressions.count)),
            type: intType
        )

        var body: [KIRInstruction] = []
        body.append(.constValue(result: paramRef, value: .symbolRef(paramSymbol)))
        body.append(.call(
            symbol: nil,
            callee: interner.intern("kk_unbox_int"),
            arguments: [paramRef],
            result: unboxedOrdinalRef,
            canThrow: false,
            thrownResult: nil
        ))
        var labelCounter: Int32 = 6000

        for (ordinal, entry) in entries.enumerated() {
            let entryName = interner.resolve(entry.name)
            let helperName = interner.intern("\(entryName)$enumName")
            let resultExpr = module.arena.appendExpr(
                .temporary(Int32(module.arena.expressions.count)),
                type: stringType
            )
            let ordinalExpr = module.arena.appendExpr(
                .intLiteral(Int64(ordinal)),
                type: intType
            )
            body.append(.constValue(result: ordinalExpr, value: .intLiteral(Int64(ordinal))))
            let nextLabel = labelCounter
            labelCounter += 1
            let matchLabel = labelCounter
            labelCounter += 1
            body.append(.jumpIfEqual(lhs: unboxedOrdinalRef, rhs: ordinalExpr, target: matchLabel))
            body.append(.jump(nextLabel))
            body.append(.label(matchLabel))
            body.append(.call(
                symbol: nil,
                callee: helperName,
                arguments: [],
                result: resultExpr,
                canThrow: false,
                thrownResult: nil
            ))
            body.append(.returnValue(resultExpr))
            body.append(.label(nextLabel))
        }
        let emptyExpr = module.arena.appendExpr(
            .stringLiteral(interner.intern("")),
            type: stringType
        )
        body.append(.constValue(result: emptyExpr, value: .stringLiteral(interner.intern(""))))
        body.append(.returnValue(emptyExpr))

        let signature = FunctionSignature(
            parameterTypes: [intType],
            returnType: stringType,
            isSuspend: false,
            valueParameterSymbols: [paramSymbol],
            valueParameterHasDefaultValues: [false],
            valueParameterIsVararg: [false]
        )
        appendSyntheticFunctionIfNeeded(
            name: name,
            owner: owner,
            module: module,
            sema: sema,
            signature: signature,
            params: [param],
            body: body,
            existingFunctionSymbols: existingFunctionSymbols
        )
    }

    /// Synthesizes `valueOf(String)` which does a linear comparison of the
    /// argument against each entry name and returns the matching ordinal.
    /// If no match is found, it calls `kk_enum_valueOf_throw` to signal an
    /// IllegalArgumentException. When owner is the companion, uses the stub's
    /// symbol so Color.valueOf resolves to the same KIR function.
    private func appendSyntheticEnumValueOfIfNeeded(
        name: InternedString,
        owner: SemanticSymbol,
        enumType: TypeID,
        entries: [SemanticSymbol],
        module: KIRModule,
        sema: SemaModule,
        existingFunctionSymbols: Set<SymbolID>,
        interner: StringInterner
    ) {
        let stringType = sema.types.make(.primitive(.string, .nonNull))

        let fqName = owner.fqName + [name]
        let parameterName = interner.intern("$name")
        let parameterSymbol = sema.symbols.define(
            kind: .valueParameter,
            name: parameterName,
            fqName: fqName + [parameterName],
            declSite: owner.declSite,
            visibility: .private,
            flags: [.synthetic]
        )
        let parameter = KIRParameter(symbol: parameterSymbol, type: stringType)
        let paramRef = module.arena.appendExpr(
            .symbolRef(parameterSymbol),
            type: stringType
        )

        var body: [KIRInstruction] = []
        body.append(.constValue(result: paramRef, value: .symbolRef(parameterSymbol)))

        var labelCounter: Int32 = 5000

        // For each entry, compare name and return ordinal if matched
        for (ordinal, entry) in entries.enumerated() {
            let entryNameStr = interner.intern(interner.resolve(entry.name))
            let entryNameExpr = module.arena.appendExpr(
                .stringLiteral(entryNameStr),
                type: stringType
            )
            body.append(.constValue(result: entryNameExpr, value: .stringLiteral(entryNameStr)))

            let cmpResult = module.arena.appendExpr(
                .temporary(Int32(module.arena.expressions.count)),
                type: sema.types.make(.primitive(.boolean, .nonNull))
            )
            let cmpCallee = interner.intern("kk_string_equals")
            body.append(.call(
                symbol: nil,
                callee: cmpCallee,
                arguments: [paramRef, entryNameExpr],
                result: cmpResult,
                canThrow: false,
                thrownResult: nil
            ))

            let falseExpr = module.arena.appendExpr(
                .boolLiteral(false),
                type: sema.types.make(.primitive(.boolean, .nonNull))
            )
            body.append(.constValue(result: falseExpr, value: .boolLiteral(false)))

            let nextLabel = labelCounter
            labelCounter += 1

            body.append(.jumpIfEqual(lhs: cmpResult, rhs: falseExpr, target: nextLabel))

            // Match found – return ordinal (enum values are represented as ordinals)
            let ordinalExpr = module.arena.appendExpr(
                .intLiteral(Int64(ordinal)),
                type: enumType
            )
            body.append(.constValue(result: ordinalExpr, value: .intLiteral(Int64(ordinal))))
            body.append(.returnValue(ordinalExpr))

            body.append(.label(nextLabel))
        }

        // No match – call throw helper
        let throwCallee = interner.intern("kk_enum_valueOf_throw")
        let throwResult = module.arena.appendExpr(
            .temporary(Int32(module.arena.expressions.count)),
            type: sema.types.nothingType
        )
        body.append(.call(
            symbol: nil,
            callee: throwCallee,
            arguments: [paramRef],
            result: throwResult,
            canThrow: true,
            thrownResult: nil
        ))
        body.append(.returnValue(throwResult))

        let companionType = sema.types.make(.classType(ClassType(
            classSymbol: owner.id,
            args: [],
            nullability: .nonNull
        )))
        let signature = FunctionSignature(
            receiverType: companionType,
            parameterTypes: [stringType],
            returnType: enumType,
            isSuspend: false,
            valueParameterSymbols: [parameterSymbol],
            valueParameterHasDefaultValues: [false],
            valueParameterIsVararg: [false]
        )

        // Use existing stub symbol when companion has valueOf from Sema
        let existingValueOf = sema.symbols.lookupAll(fqName: fqName).first { candidate in
            guard let sym = sema.symbols.symbol(candidate),
                  sym.kind == .function,
                  sym.flags.contains(.synthetic),
                  sema.symbols.parentSymbol(for: candidate) == owner.id
            else { return false }
            return true
        }
        if let existingSymbol = existingValueOf, !existingFunctionSymbols.contains(existingSymbol) {
            let receiverParam = KIRParameter(
                symbol: sema.symbols.define(
                    kind: .valueParameter,
                    name: interner.intern("$self"),
                    fqName: fqName + [interner.intern("$self")],
                    declSite: owner.declSite,
                    visibility: .private,
                    flags: [.synthetic]
                ),
                type: companionType
            )
            appendSyntheticFunctionWithSymbol(
                functionSymbol: existingSymbol,
                name: name,
                module: module,
                sema: sema,
                signature: signature,
                params: [receiverParam, parameter],
                body: body
            )
        } else {
            let receiverParam = KIRParameter(
                symbol: sema.symbols.define(
                    kind: .valueParameter,
                    name: interner.intern("$self"),
                    fqName: fqName + [interner.intern("$self")],
                    declSite: owner.declSite,
                    visibility: .private,
                    flags: [.synthetic]
                ),
                type: companionType
            )
            appendSyntheticFunctionIfNeeded(
                name: name,
                owner: owner,
                module: module,
                sema: sema,
                signature: signature,
                params: [receiverParam, parameter],
                body: body,
                existingFunctionSymbols: existingFunctionSymbols
            )
        }
    }

    /// Synthesizes `__enum_static_init_<ClassName>()` which initialises the
    /// global slots for each enum entry with their ordinal values, and ensures
    /// KIRGlobal declarations exist so that codegen allocates LLVM global
    /// variables for the entries. These globals model ordinal storage, so the
    /// slot declarations and writes must stay typed as `Int`.
    private func appendSyntheticEnumStaticInitIfNeeded(
        owner: SemanticSymbol,
        entries: [SemanticSymbol],
        module: KIRModule,
        sema: SemaModule,
        existingFunctionSymbols: Set<SymbolID>,
        interner: StringInterner
    ) {
        guard !entries.isEmpty else { return }

        let intType = sema.types.make(.primitive(.int, .nonNull))
        // Collect existing global symbols so we don't create duplicates.
        var existingGlobalSymbols = Set(module.arena.declarations.compactMap { decl -> SymbolID? in
            guard case let .global(global) = decl else {
                return nil
            }
            return global.symbol
        })

        // Ensure a KIRGlobal exists for every entry field. BuildKIR emits these
        // for `enumEntryDecl` nodes, but when the enum class comes from a
        // nominalType-only module (e.g. library metadata) the globals may be
        // absent. Adding them here is idempotent thanks to the guard.
        for entry in entries {
            if !existingGlobalSymbols.contains(entry.id) {
                _ = module.arena.appendDecl(.global(KIRGlobal(symbol: entry.id, type: intType)))
                existingGlobalSymbols.insert(entry.id)
            }
        }

        // Build the static initialiser body.
        let ownerName = interner.resolve(owner.name)
        let initName = interner.intern("__enum_static_init_\(ownerName)")

        var body: [KIRInstruction] = []

        for (ordinal, entry) in entries.enumerated() {
            // Produce the ordinal value.
            let ordinalExpr = module.arena.appendExpr(
                .intLiteral(Int64(ordinal)),
                type: intType
            )
            body.append(.constValue(result: ordinalExpr, value: .intLiteral(Int64(ordinal))))

            // Reference the entry's global slot.
            let entryRef = module.arena.appendExpr(
                .symbolRef(entry.id),
                type: intType
            )
            body.append(.constValue(result: entryRef, value: .symbolRef(entry.id)))

            // Store ordinal into the global slot.
            body.append(.copy(from: ordinalExpr, to: entryRef))
        }

        body.append(.returnUnit)

        let unitType = sema.types.unitType
        let signature = FunctionSignature(parameterTypes: [], returnType: unitType, isSuspend: false)

        appendSyntheticFunctionIfNeeded(
            name: initName,
            owner: owner,
            module: module,
            sema: sema,
            signature: signature,
            params: [],
            body: body,
            existingFunctionSymbols: existingFunctionSymbols
        )
    }

    /// Appends a KIR function using an existing symbol (e.g. from Sema). Used when the symbol
    /// was already registered for resolution so call sites bind to the same symbol.
    private func appendSyntheticFunctionWithSymbol(
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

    private func appendSyntheticFunctionIfNeeded(
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
