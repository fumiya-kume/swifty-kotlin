
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

        appendReferencedSyntheticMemoryModelNominalIfNeeded(
            module: module,
            sema: sema,
            interner: ctx.interner
        )
        appendReferencedSourceBackedOsFamilyNominalIfNeeded(
            module: module,
            sema: sema,
            interner: ctx.interner
        )
        appendReferencedSourceBackedKVarianceNominalIfNeeded(
            module: module,
            sema: sema,
            interner: ctx.interner
        )

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

        var enumStaticInitCallees: [(name: InternedString, symbol: SymbolID)] = []

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
                let entries = enumEntrySymbols(owner: nominalSymbol, symbols: sema.symbols)
                if !entries.isEmpty {
                    let initName = ctx.interner.intern("__enum_static_init_\(ctx.interner.resolve(nominalSymbol.name))")
                    if let initSymbol = sema.symbols.lookup(fqName: nominalSymbol.fqName + [initName]) {
                        enumStaticInitCallees.append((initName, initSymbol))
                    }
                }
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

        // `__enum_static_init_<Class>` populates the global ordinal slots that
        // equality comparisons and `when` branches read back. Nothing else
        // ever calls it, so without this the globals stay at their
        // zero-initialized default and every entry of a given enum class
        // compares equal. Inject one call per enum class at the very start of
        // `main`, mirroring how top-level property/companion initializers are
        // threaded in by `postProcessTopLevelInitializersAndDelegates`.
        if !enumStaticInitCallees.isEmpty {
            let mainName = ctx.interner.intern("main")
            let unitType = sema.types.unitType
            module.arena.transformFunctions { function in
                guard function.name == mainName else {
                    return function
                }
                var initInstructions: [KIRInstruction] = []
                for callee in enumStaticInitCallees {
                    let result = module.arena.appendTemporary(type: unitType)
                    initInstructions.append(.call(
                        symbol: callee.symbol,
                        callee: callee.name,
                        arguments: [],
                        result: result,
                        canThrow: false,
                        thrownResult: nil
                    ))
                }
                var updated = function
                if let first = updated.body.first, case .beginBlock = first {
                    updated.replaceBody([first] + initInstructions + updated.body.dropFirst())
                } else {
                    updated.replaceBody(initInstructions + updated.body)
                }
                return updated
            }
        }

        // Rewrite symbolRef references to synthetic enum entries (e.g.
        // RegexOption.DOT_MATCHES_ALL) into boxed ordinal int literals.
        // User-defined enum entries are backed by global variables, but
        // synthetic entries have no globals — so we inline the ordinal.
        rewriteSyntheticEnumEntryRefs(module: module, sema: sema)

        module.recordLowering(Self.name)
    }

    /// Makes the synthetic Native MemoryModel visible to the shared enum
    /// synthesis pass only when one of its generated APIs is referenced.
    private func appendReferencedSyntheticMemoryModelNominalIfNeeded(
        module: KIRModule,
        sema: SemaModule,
        interner: StringInterner
    ) {
        let memoryModelFQName = [
            interner.intern("kotlin"),
            interner.intern("native"),
            interner.intern("MemoryModel"),
        ]
        guard let memoryModelSymbol = sema.symbols.lookup(fqName: memoryModelFQName),
              let memoryModel = sema.symbols.symbol(memoryModelSymbol),
              memoryModel.kind == .enumClass
        else {
            return
        }

        let generatedMemberNames = [
            interner.intern("entries"),
            interner.intern("valueOf"),
            interner.intern("values"),
        ]
        let generatedMembers = Set(generatedMemberNames.flatMap { name in
            sema.symbols.lookupAll(fqName: memoryModelFQName + [name])
        })
        guard !generatedMembers.isEmpty else {
            return
        }

        let isReferenced = sema.bindings.identifierSymbols.values.contains {
            generatedMembers.contains($0)
        } || sema.bindings.callBindings.values.contains {
            generatedMembers.contains($0.chosenCallee)
        }
        guard isReferenced else {
            return
        }

        let alreadyDeclared = module.arena.declarations.contains { declaration in
            guard case let .nominalType(nominal) = declaration else {
                return false
            }
            return nominal.symbol == memoryModelSymbol
        }
        guard !alreadyDeclared else {
            return
        }
        _ = module.arena.appendDecl(.nominalType(KIRNominalType(symbol: memoryModelSymbol)))
    }

    /// Makes the bundled Native OsFamily enum available to the shared enum
    /// synthesis pass when a consumer KIR references one of its generated APIs.
    /// Bundled source declarations are omitted from consumer KIR, but their
    /// source-backed nominal identity is still required by enum helper bodies.
    private func appendReferencedSourceBackedOsFamilyNominalIfNeeded(
        module: KIRModule,
        sema: SemaModule,
        interner: StringInterner
    ) {
        let osFamilyFQName = [
            interner.intern("kotlin"),
            interner.intern("native"),
            interner.intern("OsFamily"),
        ]
        guard let osFamilySymbol = sema.symbols.lookup(fqName: osFamilyFQName),
              let osFamily = sema.symbols.symbol(osFamilySymbol),
              osFamily.kind == .enumClass,
              sema.symbols.isSourceBackedSymbol(osFamilySymbol)
        else {
            return
        }

        var generatedMembers = Set(
            sema.symbols.lookupAll(fqName: osFamilyFQName + [interner.intern("values")])
        )
        if let companionSymbol = sema.symbols.companionObjectSymbol(for: osFamilySymbol),
           let companion = sema.symbols.symbol(companionSymbol)
        {
            generatedMembers.formUnion(
                sema.symbols.lookupAll(fqName: companion.fqName + [interner.intern("entries")])
            )
            generatedMembers.formUnion(
                sema.symbols.lookupAll(fqName: companion.fqName + [interner.intern("valueOf")])
            )
        }
        guard !generatedMembers.isEmpty else {
            return
        }

        let isReferenced = sema.bindings.identifierSymbols.values.contains {
            generatedMembers.contains($0)
        } || sema.bindings.callBindings.values.contains {
            generatedMembers.contains($0.chosenCallee)
        } || sema.bindings.exprTypes.values.contains {
            guard case let .classType(classType) = sema.types.kind(of: $0) else {
                return false
            }
            return classType.classSymbol == osFamilySymbol
        }
        guard isReferenced else {
            return
        }

        let alreadyDeclared = module.arena.declarations.contains { declaration in
            guard case let .nominalType(nominal) = declaration else {
                return false
            }
            return nominal.symbol == osFamilySymbol
        }
        guard !alreadyDeclared else {
            return
        }
        _ = module.arena.appendDecl(.nominalType(KIRNominalType(symbol: osFamilySymbol)))
    }

    /// Makes the bundled KVariance enum available to the shared enum
    /// synthesis pass when a consumer KIR references its generated APIs.
    /// Bundled source declarations are omitted from consumer KIR, but their
    /// source-backed nominal identity is required by enum helper bodies.
    private func appendReferencedSourceBackedKVarianceNominalIfNeeded(
        module: KIRModule,
        sema: SemaModule,
        interner: StringInterner
    ) {
        let kVarianceFQName = [
            interner.intern("kotlin"),
            interner.intern("reflect"),
            interner.intern("KVariance"),
        ]
        guard let kVarianceSymbol = sema.symbols.lookup(fqName: kVarianceFQName),
              let kVariance = sema.symbols.symbol(kVarianceSymbol),
              kVariance.kind == .enumClass,
              sema.symbols.isSourceBackedSymbol(kVarianceSymbol)
        else {
            return
        }

        var generatedMembers = Set(
            sema.symbols.lookupAll(fqName: kVarianceFQName + [interner.intern("values")])
        )
        if let companionSymbol = sema.symbols.companionObjectSymbol(for: kVarianceSymbol),
           let companion = sema.symbols.symbol(companionSymbol)
        {
            generatedMembers.formUnion(
                sema.symbols.lookupAll(fqName: companion.fqName + [interner.intern("entries")])
            )
            generatedMembers.formUnion(
                sema.symbols.lookupAll(fqName: companion.fqName + [interner.intern("valueOf")])
            )
        }
        guard !generatedMembers.isEmpty else {
            return
        }

        let isReferenced = sema.bindings.identifierSymbols.values.contains {
            generatedMembers.contains($0)
        } || sema.bindings.callBindings.values.contains {
            generatedMembers.contains($0.chosenCallee)
        } || sema.bindings.exprTypes.values.contains {
            guard case let .classType(classType) = sema.types.kind(of: $0) else {
                return false
            }
            return classType.classSymbol == kVarianceSymbol
        }
        guard isReferenced else {
            return
        }

        let alreadyDeclared = module.arena.declarations.contains { declaration in
            guard case let .nominalType(nominal) = declaration else {
                return false
            }
            return nominal.symbol == kVarianceSymbol
        }
        guard !alreadyDeclared else {
            return
        }
        _ = module.arena.appendDecl(.nominalType(KIRNominalType(symbol: kVarianceSymbol)))
    }

    /// Replaces `constValue(result: r, value: .symbolRef(sym))` where `sym`
    /// is a synthetic field owned by a synthetic enum class with
    /// `constValue(result: r, value: .intLiteral(ordinal))` followed by a
    /// `call kk_box_int` so the value is a boxed enum ordinal.
    private func rewriteSyntheticEnumEntryRefs(
        module: KIRModule,
        sema: SemaModule
    ) {
        // Build a lookup: syntheticEnumEntrySymbol -> ordinal.
        // Use `isSourceBackedSymbol` rather than the `synthetic` flag so that
        // real source-backed enum entries (including those imported from a
        // precompiled .kklib) keep their global-object symbolRef; only
        // compiler-synthesised enum entries (e.g. RegexOption.DOT_MATCHES_ALL)
        // are inlined as raw ordinals.
        var syntheticEntryOrdinal: [SymbolID: Int] = [:]
        for sym in sema.symbols.allSymbols() {
            guard sym.kind == .field,
                  !sema.symbols.isSourceBackedSymbol(sym.id),
                  sym.fqName.count >= 2
            else {
                continue
            }
            let parentFQ = Array(sym.fqName.dropLast())
            guard let parentSymbol = sema.symbols.lookup(fqName: parentFQ),
                  let parentInfo = sema.symbols.symbol(parentSymbol),
                  parentInfo.kind == .enumClass,
                  !sema.symbols.isSourceBackedSymbol(parentSymbol)
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
        let stringType = sema.types.stringType
        for (ordinal, entry) in entries.enumerated() {
            appendSyntheticCountFunctionIfNeeded(
                name: NameMangler.enumEntryOrdinalHelperName(for: entry, interner: ctx.interner),
                owner: nominalSymbol, value: Int64(ordinal),
                returnType: intType, module: module, sema: sema,
                existingFunctionSymbols: existingFunctionSymbols
            )
            appendSyntheticStringFunctionIfNeeded(
                name: NameMangler.enumEntryNameHelperName(for: entry, interner: ctx.interner),
                owner: nominalSymbol, value: entry.name,
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
            enumName: nominalSymbol.fqName.map(ctx.interner.resolve).joined(separator: "."),
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
            let resultExpr = module.arena.appendTemporary(type: returnType
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
        let fieldOffsets = symbols.nominalLayout(for: owner.id)?.fieldOffsets ?? [:]
        return symbols.children(ofFQName: owner.fqName)
            .compactMap { symbols.symbol($0) }
            .filter { $0.kind == .field }
            .sorted(by: {
                // Source-backed entries have precise declaration ranges.
                let lhsDeclOffset = $0.declSite?.start.offset
                let rhsDeclOffset = $1.declSite?.start.offset
                if let lhsDeclOffset, let rhsDeclOffset, lhsDeclOffset != rhsDeclOffset {
                    return lhsDeclOffset < rhsDeclOffset
                }
                if (lhsDeclOffset == nil) != (rhsDeclOffset == nil) {
                    return lhsDeclOffset != nil
                }
                // Imported library entries have no source declaration range;
                // their metadata field offsets preserve declaration order.
                let lhsFieldOffset = fieldOffsets[$0.id] ?? Int.max
                let rhsFieldOffset = fieldOffsets[$1.id] ?? Int.max
                if lhsFieldOffset != rhsFieldOffset {
                    return lhsFieldOffset < rhsFieldOffset
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
        let resultExpr = module.arena.appendTemporary(type: returnType
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
        let resultExpr = module.arena.appendTemporary(type: returnType
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
        // Preserve the generic receiver contract collected for source-backed data
        // class members when the lowering body is synthesized with erased KIR types.
        let effectiveSignature: FunctionSignature = if
            signature.classTypeParameterCount == 0,
            let existingSignature = sema.symbols.functionSignature(for: functionSymbol),
            existingSignature.classTypeParameterCount > 0
        {
            FunctionSignature(
                receiverType: existingSignature.receiverType,
                parameterTypes: signature.parameterTypes,
                returnType: existingSignature.returnType,
                isSuspend: signature.isSuspend,
                canThrow: signature.canThrow,
                valueParameterSymbols: signature.valueParameterSymbols,
                valueParameterHasDefaultValues: signature.valueParameterHasDefaultValues,
                valueParameterIsVararg: signature.valueParameterIsVararg,
                valueParameterAllowsNonLocalReturn: signature.valueParameterAllowsNonLocalReturn,
                typeParameterSymbols: existingSignature.typeParameterSymbols,
                reifiedTypeParameterIndices: existingSignature.reifiedTypeParameterIndices,
                typeParameterUpperBounds: existingSignature.typeParameterUpperBounds,
                typeParameterUpperBoundsList: existingSignature.typeParameterUpperBoundsList,
                classTypeParameterCount: existingSignature.classTypeParameterCount
            )
        } else {
            signature
        }
        sema.symbols.setFunctionSignature(effectiveSignature, for: functionSymbol)
        _ = module.arena.appendDecl(.function(
            KIRFunction(
                symbol: functionSymbol,
                name: name,
                params: params,
                returnType: effectiveSignature.returnType,
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
        sema.symbols.setParentSymbol(owner.id, for: functionSymbol)
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
                valueParameterAllowsNonLocalReturn: signature.valueParameterAllowsNonLocalReturn.isEmpty
                    ? params.map { _ in true }
                    : signature.valueParameterAllowsNonLocalReturn,
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
