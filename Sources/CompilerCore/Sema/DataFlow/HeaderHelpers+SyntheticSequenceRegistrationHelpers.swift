// swiftlint:disable file_length

/// `kotlin.sequences.Sequence` compatibility helpers:
/// source-aware fallback registration, builder/iterator builder, factory,
/// and generic-sequence helpers.
///
/// Split out from `HeaderHelpers+SyntheticTODOAndIOStubs.swift`.
extension DataFlowSemaPhase {
    func registerSyntheticSystemMember(
        ownerSymbol: SymbolID,
        ownerType: TypeID,
        name: String,
        externalLinkName: String,
        returnType: TypeID,
        parameters: [(name: String, type: TypeID)],
        symbols: SymbolTable,
        interner: StringInterner
    ) {
        guard let ownerInfo = symbols.symbol(ownerSymbol) else {
            return
        }
        registerSyntheticFunctionStub(
            named: name,
            ownerFQName: ownerInfo.fqName,
            parentSymbol: ownerSymbol,
            receiverType: ownerType,
            parameters: syntheticFunctionParameters(parameters),
            returnType: returnType,
            externalLinkName: externalLinkName,
            matchReturnType: true,
            symbols: symbols,
            interner: interner
        )
    }

    func registerSyntheticTopLevelFunction(
        named name: String,
        packageFQName: [InternedString],
        parameters: [(name: String, type: TypeID)],
        returnType: TypeID,
        externalLinkName: String,
        annotations: [MetadataAnnotationRecord] = [],
        stdlibSpecialCallKind: StdlibSpecialCallKind? = nil,
        symbols: SymbolTable,
        interner: StringInterner
    ) {
        let functionSymbol = registerSyntheticFunctionStub(
            named: name,
            ownerFQName: packageFQName,
            parentSymbol: symbols.lookup(fqName: packageFQName),
            parameters: syntheticFunctionParameters(parameters),
            returnType: returnType,
            externalLinkName: externalLinkName,
            annotations: annotations,
            matchReturnType: true,
            symbols: symbols,
            interner: interner
        )
        if let stdlibSpecialCallKind {
            symbols.setStdlibSpecialCallKind(stdlibSpecialCallKind, for: functionSymbol)
        }
    }


    func registerSyntheticSequenceStub(
        packageFQName: [InternedString],
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner
    ) -> SymbolID {
        // KSP-701: only the source-less fallback may synthesize Sequence.
        // Bundled source declarations, including Sequence.iterator, remain authoritative.
        let sequenceFQName = packageFQName + [interner.intern("Sequence")]
        if let existing = symbols.lookup(fqName: sequenceFQName),
           symbols.isSourceBackedSymbol(existing) {
            return existing
        }
        let kotlinCollectionsPkg: [InternedString] = [
            interner.intern("kotlin"), interner.intern("collections")
        ]
        return ensureSyntheticSequenceStub(
            symbols: symbols,
            types: types,
            interner: interner,
            kotlinCollectionsPkg: kotlinCollectionsPkg,
            bundledIndex: BundledSyntheticStubRegistration.bundledIndex
        )
    }

    /// Idempotent fallback for contexts without the bundled Sequence declaration.
    func ensureSyntheticSequenceStub(
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner,
        kotlinCollectionsPkg: [InternedString],
        bundledIndex: BundledDeclarationIndex = .empty
    ) -> SymbolID {
        let kotlinSequencesPkg: [InternedString] = [
            interner.intern("kotlin"), interner.intern("sequences")
        ]
        if symbols.lookup(fqName: kotlinSequencesPkg) == nil {
            _ = symbols.define(
                kind: .package,
                name: interner.intern("sequences"),
                fqName: kotlinSequencesPkg,
                declSite: nil,
                visibility: .public,
                flags: [.synthetic]
            )
        }

        let sequenceName = interner.intern("Sequence")
        let sequenceFQName = kotlinSequencesPkg + [sequenceName]
        let sequenceSymbol: SymbolID = if let existing = symbols.lookup(fqName: sequenceFQName) {
            existing
        } else {
            symbols.define(
                kind: .interface,
                name: sequenceName,
                fqName: sequenceFQName,
                declSite: nil,
                visibility: .public,
                flags: [.synthetic]
            )
        }

        let seqTypeParamName = interner.intern("T")
        let seqTypeParamFQName = sequenceFQName + [seqTypeParamName]
        if symbols.lookup(fqName: seqTypeParamFQName) == nil {
            let seqTypeParamSymbol = symbols.define(
                kind: .typeParameter,
                name: seqTypeParamName,
                fqName: seqTypeParamFQName,
                declSite: nil,
                visibility: .private,
                flags: []
            )
            types.setNominalTypeParameterSymbols([seqTypeParamSymbol], for: sequenceSymbol)
            types.setNominalTypeParameterVariances([.out], for: sequenceSymbol)
        }

        // Register iterator() independently of the type parameter block above,
        // so it's added even when Sequence<T> was created elsewhere.
        let iterFnName = interner.intern("iterator")
        let iterFnFQName = sequenceFQName + [iterFnName]
        let hasSourceIterator = bundledIndex.contains(
            owner: sequenceFQName,
            name: iterFnName,
            arity: 0
        )
        if !hasSourceIterator, symbols.lookup(fqName: iterFnFQName) == nil {
            if let seqTypeParamSymbol = symbols.lookup(fqName: seqTypeParamFQName) {
                let seqTypeParamType = types.make(.typeParam(TypeParamType(
                    symbol: seqTypeParamSymbol, nullability: .nonNull
                )))
                let iteratorName = interner.intern("Iterator")
                let iteratorFQName = kotlinCollectionsPkg + [iteratorName]
                if let iteratorSymbol = symbols.lookup(fqName: iteratorFQName) {
                    let iteratorReturnType = types.make(.classType(ClassType(
                        classSymbol: iteratorSymbol,
                        args: [.out(seqTypeParamType)],
                        nullability: .nonNull
                    )))
                    let iterFnSymbol = symbols.define(
                        kind: .function,
                        name: iterFnName,
                        fqName: iterFnFQName,
                        declSite: nil,
                        visibility: .public,
                        flags: [.synthetic, .operatorFunction]
                    )
                    symbols.setParentSymbol(sequenceSymbol, for: iterFnSymbol)
                    let seqReceiverType = types.make(.classType(ClassType(
                        classSymbol: sequenceSymbol,
                        args: [.out(seqTypeParamType)],
                        nullability: .nonNull
                    )))
                    symbols.setFunctionSignature(
                        FunctionSignature(
                            receiverType: seqReceiverType,
                            parameterTypes: [],
                            returnType: iteratorReturnType,
                            typeParameterSymbols: [seqTypeParamSymbol],
                            classTypeParameterCount: 1
                        ),
                        for: iterFnSymbol
                    )
                }
            }
        }

        return sequenceSymbol
    }

    func registerSyntheticSequenceBuilderStub(
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner
    ) {
        let kotlinSequencesPkg = ensureSyntheticPackageHierarchy(
            fqName: [interner.intern("kotlin"), interner.intern("sequences")],
            symbols: symbols
        )
        let sequenceSymbol = registerSyntheticSequenceStub(
            packageFQName: kotlinSequencesPkg,
            symbols: symbols,
            types: types,
            interner: interner
        )

        let scopeName = interner.intern("SequenceScope")
        let scopeFQName = kotlinSequencesPkg + [scopeName]
        let scopeSymbol: SymbolID
        if let existing = symbols.lookup(fqName: scopeFQName) {
            scopeSymbol = existing
        } else {
            let sym = symbols.define(
                kind: .class,
                name: scopeName,
                fqName: scopeFQName,
                declSite: nil,
                visibility: .public,
                flags: [.synthetic]
            )
            if let packageSymbol = symbols.lookup(fqName: kotlinSequencesPkg) {
                symbols.setParentSymbol(packageSymbol, for: sym)
            }
            scopeSymbol = sym
        }
        let scopeTypeParamName = interner.intern("T")
        let scopeTypeParamFQName = scopeFQName + [scopeTypeParamName]
        let scopeTypeParamSymbol: SymbolID
        if let existing = symbols.lookup(fqName: scopeTypeParamFQName) {
            scopeTypeParamSymbol = existing
        } else {
            let param = symbols.define(
                kind: .typeParameter,
                name: scopeTypeParamName,
                fqName: scopeTypeParamFQName,
                declSite: nil,
                visibility: .private,
                flags: []
            )
            symbols.setParentSymbol(scopeSymbol, for: param)
            scopeTypeParamSymbol = param
        }
        types.setNominalTypeParameterSymbols([scopeTypeParamSymbol], for: scopeSymbol)
        types.setNominalTypeParameterVariances([.in], for: scopeSymbol)

        let scopeTypeParamType = types.make(.typeParam(TypeParamType(symbol: scopeTypeParamSymbol)))
        let scopeReceiverType = types.make(.classType(ClassType(
            classSymbol: scopeSymbol,
            args: [.invariant(scopeTypeParamType)],
            nullability: .nonNull
        )))
        let iteratorType = nominalSequenceParameterType(
            package: ["kotlin", "collections", "Iterator"],
            elementType: scopeTypeParamType,
            symbols: symbols,
            types: types,
            interner: interner
        )
        let iterableType = nominalSequenceParameterType(
            package: ["kotlin", "collections", "Iterable"],
            elementType: scopeTypeParamType,
            symbols: symbols,
            types: types,
            interner: interner
        )
        let sequenceType = types.make(.classType(ClassType(
            classSymbol: sequenceSymbol,
            args: [.out(scopeTypeParamType)],
            nullability: .nonNull
        )))
        registerSequenceScopeMember(
            named: "yield",
            sequenceScopeSymbol: scopeSymbol,
            sequenceScopeFQName: scopeFQName,
            receiverType: scopeReceiverType,
            parameters: [(name: "value", type: scopeTypeParamType)],
            returnType: types.unitType,
            externalLinkName: "__kk_sequence_builder_yield",
            symbols: symbols,
            interner: interner
        )

        registerSequenceScopeMember(
            named: "yieldAll",
            sequenceScopeSymbol: scopeSymbol,
            sequenceScopeFQName: scopeFQName,
            receiverType: scopeReceiverType,
            parameters: [(name: "iterator", type: iteratorType)],
            returnType: types.unitType,
            externalLinkName: "__kk_sequence_builder_yieldAll",
            symbols: symbols,
            interner: interner
        )
        registerSequenceScopeMember(
            named: "yieldAll",
            sequenceScopeSymbol: scopeSymbol,
            sequenceScopeFQName: scopeFQName,
            receiverType: scopeReceiverType,
            parameters: [(name: "elements", type: iterableType)],
            returnType: types.unitType,
            externalLinkName: "__kk_sequence_builder_yieldAll",
            symbols: symbols,
            interner: interner
        )
        registerSequenceScopeMember(
            named: "yieldAll",
            sequenceScopeSymbol: scopeSymbol,
            sequenceScopeFQName: scopeFQName,
            receiverType: scopeReceiverType,
            parameters: [(name: "sequence", type: sequenceType)],
            returnType: types.unitType,
            externalLinkName: "__kk_sequence_builder_yieldAll",
            symbols: symbols,
            interner: interner
        )

        let functionName = interner.intern("sequence")
        let functionFQName = kotlinSequencesPkg + [functionName]
        guard symbols.lookup(fqName: functionFQName) == nil else {
            return
        }

        let functionSymbol = symbols.define(
            kind: .function,
            name: functionName,
            fqName: functionFQName,
            declSite: nil,
            visibility: .public,
            flags: [.synthetic]
        )
        if let packageSymbol = symbols.lookup(fqName: kotlinSequencesPkg) {
            symbols.setParentSymbol(packageSymbol, for: functionSymbol)
        }
        symbols.setExternalLinkName("__kk_sequence_builder_build", for: functionSymbol)

        let functionTypeParamName = interner.intern("T")
        let functionTypeParamFQName = functionFQName + [functionTypeParamName]
        let functionTypeParamSymbol = symbols.define(
            kind: .typeParameter,
            name: functionTypeParamName,
            fqName: functionTypeParamFQName,
            declSite: nil,
            visibility: .private,
            flags: []
        )
        symbols.setParentSymbol(functionSymbol, for: functionTypeParamSymbol)

        let builderTypeParamType = types.make(.typeParam(TypeParamType(symbol: functionTypeParamSymbol)))
        let sequenceReturnType = types.make(.classType(ClassType(
            classSymbol: sequenceSymbol,
            args: [.out(builderTypeParamType)],
            nullability: .nonNull
        )))
        let builderScopeType = types.make(.classType(ClassType(
            classSymbol: scopeSymbol,
            args: [.invariant(builderTypeParamType)],
            nullability: .nonNull
        )))
        let blockType = types.make(.functionType(FunctionType(
            receiver: builderScopeType,
            params: [],
            returnType: types.unitType,
            isSuspend: true
        )))

        let blockParamName = interner.intern("block")
        let blockParamSymbol = symbols.define(
            kind: .valueParameter,
            name: blockParamName,
            fqName: functionFQName + [blockParamName],
            declSite: nil,
            visibility: .private,
            flags: [.synthetic]
        )
        symbols.setParentSymbol(functionSymbol, for: blockParamSymbol)

        symbols.setFunctionSignature(
            FunctionSignature(
                parameterTypes: [blockType],
                returnType: sequenceReturnType,
                valueParameterSymbols: [blockParamSymbol],
                valueParameterHasDefaultValues: [false],
                valueParameterIsVararg: [false],
                typeParameterSymbols: [functionTypeParamSymbol]
            ),
            for: functionSymbol
        )
    }

    private func nominalSequenceParameterType(
        package: [String],
        elementType: TypeID,
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner
    ) -> TypeID {
        let fqName = package.map { interner.intern($0) }
        guard let symbol = symbols.lookup(fqName: fqName) else {
            return types.anyType
        }
        return types.make(.classType(ClassType(
            classSymbol: symbol,
            args: [.out(elementType)],
            nullability: .nonNull
        )))
    }

    // STDLIB-331/564: iterator {} builder → Iterator<T>
    // Mirrors registerSyntheticSequenceBuilderStub but returns Iterator<T>
    // instead of Sequence<T>, and reuses the SequenceScope<T> receiver for yield().
    func registerSyntheticIteratorBuilderStub(
        packageFQName: [InternedString],
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner
    ) {
        // Reuse the SequenceScope class registered by sequence {} builder.
        let scopeName = interner.intern("SequenceScope")
        let scopeFQName = packageFQName + [scopeName]
        let scopeSymbol: SymbolID
        if let existing = symbols.lookup(fqName: scopeFQName) {
            scopeSymbol = existing
        } else {
            let sym = symbols.define(
                kind: .class,
                name: scopeName,
                fqName: scopeFQName,
                declSite: nil,
                visibility: .public,
                flags: [.synthetic]
            )
            if let packageSymbol = symbols.lookup(fqName: packageFQName) {
                symbols.setParentSymbol(packageSymbol, for: sym)
            }
            scopeSymbol = sym
        }

        let functionName = interner.intern("iterator")
        let functionFQName = packageFQName + [functionName]
        guard symbols.lookup(fqName: functionFQName) == nil else {
            return
        }

        let functionSymbol = symbols.define(
            kind: .function,
            name: functionName,
            fqName: functionFQName,
            declSite: nil,
            visibility: .public,
            flags: [.synthetic]
        )
        if let packageSymbol = symbols.lookup(fqName: packageFQName) {
            symbols.setParentSymbol(packageSymbol, for: functionSymbol)
        }
        symbols.setExternalLinkName("__kk_iterator_builder_build", for: functionSymbol)

        let functionTypeParamName = interner.intern("T")
        let functionTypeParamFQName = functionFQName + [functionTypeParamName]
        let functionTypeParamSymbol = symbols.define(
            kind: .typeParameter,
            name: functionTypeParamName,
            fqName: functionTypeParamFQName,
            declSite: nil,
            visibility: .private,
            flags: []
        )
        symbols.setParentSymbol(functionSymbol, for: functionTypeParamSymbol)

        let builderTypeParamType = types.make(.typeParam(TypeParamType(symbol: functionTypeParamSymbol)))

        // Return type: Iterator<T>
        let kotlinCollectionsPkg: [InternedString] = [interner.intern("kotlin"), interner.intern("collections")]
        let iteratorInterfaceFQName = kotlinCollectionsPkg + [interner.intern("Iterator")]
        let iteratorReturnType: TypeID
        if let iteratorSymbol = symbols.lookup(fqName: iteratorInterfaceFQName) {
            iteratorReturnType = types.make(.classType(ClassType(
                classSymbol: iteratorSymbol,
                args: [.out(builderTypeParamType)],
                nullability: .nonNull
            )))
        } else {
            iteratorReturnType = types.anyType
        }

        // Block type: SequenceScope<T>.() -> Unit  (with receiver so yield() resolves)
        let builderScopeType = types.make(.classType(ClassType(
            classSymbol: scopeSymbol,
            args: [.invariant(builderTypeParamType)],
            nullability: .nonNull
        )))
        let blockType = types.make(.functionType(FunctionType(
            receiver: builderScopeType,
            params: [],
            returnType: types.unitType,
            isSuspend: true
        )))

        let blockParamName = interner.intern("block")
        let blockParamSymbol = symbols.define(
            kind: .valueParameter,
            name: blockParamName,
            fqName: functionFQName + [blockParamName],
            declSite: nil,
            visibility: .private,
            flags: [.synthetic]
        )
        symbols.setParentSymbol(functionSymbol, for: blockParamSymbol)

        symbols.setFunctionSignature(
            FunctionSignature(
                parameterTypes: [blockType],
                returnType: iteratorReturnType,
                valueParameterSymbols: [blockParamSymbol],
                valueParameterHasDefaultValues: [false],
                valueParameterIsVararg: [false],
                typeParameterSymbols: [functionTypeParamSymbol]
            ),
            for: functionSymbol
        )
    }
}
