// swiftlint:disable file_length
// KSP-697: nominal collection shells are source-backed; this file retains residual registration.

extension DataFlowSemaPhase {
    func registerSyntheticCollectionStubs(
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner,
        bundledIndex: BundledDeclarationIndex = .empty,
        skipStats: SyntheticStubSkipStatsCollector? = nil
    ) {
        let kotlinPkg: [InternedString] = [interner.intern("kotlin")]
        if symbols.lookup(fqName: kotlinPkg) == nil {
            _ = symbols.define(
                kind: .package,
                name: interner.intern("kotlin"),
                fqName: kotlinPkg,
                declSite: nil,
                visibility: .public,
                flags: [.synthetic]
            )
        }

        let kotlinCollectionsPkg: [InternedString] = [interner.intern("kotlin"), interner.intern("collections")]
        if symbols.lookup(fqName: kotlinCollectionsPkg) == nil {
            _ = symbols.define(
                kind: .package,
                name: interner.intern("collections"),
                fqName: kotlinCollectionsPkg,
                declSite: nil,
                visibility: .public,
                flags: [.synthetic]
            )
        }

        registerSyntheticRandomAccessStub(
            symbols: symbols,
            types: types,
            interner: interner,
            kotlinCollectionsPkg: kotlinCollectionsPkg
        )

        let iterableInterfaceSymbol = registerSyntheticIterableStub(
            symbols: symbols, types: types, interner: interner,
            kotlinCollectionsPkg: kotlinCollectionsPkg
        )

        // STDLIB-021: Iterable mutable conversion members are registered later once
        // MutableList / MutableSet stubs exist — see calls below after those stubs.

        let collectionInterfaceSymbol = registerSyntheticCollectionStub(
            symbols: symbols, types: types, interner: interner,
            kotlinCollectionsPkg: kotlinCollectionsPkg,
            iterableInterfaceSymbol: iterableInterfaceSymbol,
            bundledIndex: bundledIndex,
            skipStats: skipStats
        )

        let abstractCollectionSymbol = registerSyntheticAbstractCollectionStub(
            symbols: symbols, types: types, interner: interner,
            kotlinCollectionsPkg: kotlinCollectionsPkg,
            collectionInterfaceSymbol: collectionInterfaceSymbol
        )

        let mutableIterableInterfaceSymbol = registerSyntheticMutableIterableStub(
            symbols: symbols, types: types, interner: interner,
            kotlinCollectionsPkg: kotlinCollectionsPkg,
            iterableInterfaceSymbol: iterableInterfaceSymbol
        )

        let mutableCollectionInterfaceSymbol = registerSyntheticMutableCollectionStub(
            symbols: symbols, types: types, interner: interner,
            kotlinCollectionsPkg: kotlinCollectionsPkg,
            collectionInterfaceSymbol: collectionInterfaceSymbol,
            mutableIterableInterfaceSymbol: mutableIterableInterfaceSymbol
        )

        registerSyntheticAbstractMutableCollectionStub(
            symbols: symbols, types: types, interner: interner,
            kotlinCollectionsPkg: kotlinCollectionsPkg,
            collectionInterfaceSymbol: collectionInterfaceSymbol,
            mutableCollectionInterfaceSymbol: mutableCollectionInterfaceSymbol
        )

        let listInterfaceSymbol = registerSyntheticListStub(
            symbols: symbols, types: types, interner: interner,
            kotlinCollectionsPkg: kotlinCollectionsPkg,
            collectionInterfaceSymbol: collectionInterfaceSymbol,
            bundledIndex: bundledIndex,
            skipStats: skipStats
        )

        _ = registerSyntheticAbstractListStub(
            symbols: symbols, types: types, interner: interner,
            kotlinCollectionsPkg: kotlinCollectionsPkg,
            abstractCollectionSymbol: abstractCollectionSymbol,
            listInterfaceSymbol: listInterfaceSymbol
        )

        registerSyntheticMutableListStub(
            symbols: symbols, types: types, interner: interner,
            kotlinCollectionsPkg: kotlinCollectionsPkg,
            listInterfaceSymbol: listInterfaceSymbol,
            collectionInterfaceSymbol: collectionInterfaceSymbol,
            mutableCollectionInterfaceSymbol: mutableCollectionInterfaceSymbol,
            mutableIterableInterfaceSymbol: mutableIterableInterfaceSymbol
        )

        let setInterfaceSymbol = registerSyntheticSetStub(
            symbols: symbols, types: types, interner: interner,
            kotlinCollectionsPkg: kotlinCollectionsPkg,
            collectionInterfaceSymbol: collectionInterfaceSymbol
        )

        registerSyntheticMutableSetStub(
            symbols: symbols, types: types, interner: interner,
            kotlinCollectionsPkg: kotlinCollectionsPkg,
            setInterfaceSymbol: setInterfaceSymbol,
            collectionInterfaceSymbol: collectionInterfaceSymbol,
            mutableCollectionInterfaceSymbol: mutableCollectionInterfaceSymbol,
            mutableIterableInterfaceSymbol: mutableIterableInterfaceSymbol
        )
        registerMutableCollectionIterableAddAllMembers(
            symbols: symbols,
            types: types,
            interner: interner,
            kotlinCollectionsPkg: kotlinCollectionsPkg,
            iterableInterfaceSymbol: iterableInterfaceSymbol
        )
        let mapSymbols = registerSyntheticMapStub(
            symbols: symbols, types: types, interner: interner,
            kotlinCollectionsPkg: kotlinCollectionsPkg
        )
        _ = registerSyntheticAbstractMapStub(
            symbols: symbols,
            types: types,
            interner: interner,
            kotlinCollectionsPkg: kotlinCollectionsPkg,
            mapInterfaceSymbol: mapSymbols.mapSymbol
        )

        // STDLIB-021: Collection.toMutableList() and Iterable mutable conversions
        if let mutableListSym = symbols.lookup(
            fqName: kotlinCollectionsPkg + [interner.intern("MutableList")]
        ),
        let mutableSetSym = symbols.lookup(
            fqName: kotlinCollectionsPkg + [interner.intern("MutableSet")]
        ) {
            let sequenceSymbol = ensureSyntheticSequenceStub(
                symbols: symbols,
                types: types,
                interner: interner,
                kotlinCollectionsPkg: kotlinCollectionsPkg,
                bundledIndex: bundledIndex
            )
            registerMutableCollectionSequenceAddAllMembers(
                symbols: symbols,
                types: types,
                interner: interner,
                mutableCollectionSymbol: mutableCollectionInterfaceSymbol,
                mutableListSymbol: mutableListSym,
                mutableSetSymbol: mutableSetSym,
                sequenceSymbol: sequenceSymbol
            )
        }

        registerSyntheticMutableMapStub(
            symbols: symbols, types: types, interner: interner,
            kotlinCollectionsPkg: kotlinCollectionsPkg,
            mapInterfaceSymbol: mapSymbols.mapSymbol,
            keyTypeParamSymbol: mapSymbols.keyTypeParamSymbol,
            valueTypeParamSymbol: mapSymbols.valueTypeParamSymbol
        )
        registerMapHigherOrderMembers(
            symbols: symbols, types: types, interner: interner,
            kotlinCollectionsPkg: kotlinCollectionsPkg,
            mapInterfaceSymbol: mapSymbols.mapSymbol,
            keyTypeParamSymbol: mapSymbols.keyTypeParamSymbol,
            valueTypeParamSymbol: mapSymbols.valueTypeParamSymbol,
            collectionInterfaceSymbol: collectionInterfaceSymbol,
            bundledIndex: bundledIndex,
            skipStats: skipStats
        )

        // KSP-625: ArrayDeque is provided by bundled Kotlin source
        // (Stdlib/kotlin/collections/ArrayDeque.kt), so no synthetic stub is
        // registered for it here.

        registerSyntheticCollectionFactoryStubs(
            symbols: symbols, types: types, interner: interner,
            kotlinCollectionsPkg: kotlinCollectionsPkg,
            bundledIndex: bundledIndex,
            skipStats: skipStats
        )

        registerSyntheticArrayStubs(
            symbols: symbols, types: types, interner: interner,
            skipStats: skipStats
        )
        registerMutableCollectionArrayAddAllMembers(
            symbols: symbols,
            types: types,
            interner: interner,
            kotlinCollectionsPkg: kotlinCollectionsPkg
        )
    }

    /// Register `kotlin.collections.RandomAccess` marker interface surface.
    private func registerSyntheticRandomAccessStub(
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner,
        kotlinCollectionsPkg: [InternedString]
    ) {
        let randomAccessSymbol = ensureInterfaceSymbol(
            named: "RandomAccess",
            in: kotlinCollectionsPkg,
            symbols: symbols,
            interner: interner
        )
        let randomAccessType = types.make(.classType(ClassType(
            classSymbol: randomAccessSymbol,
            args: [],
            nullability: .nonNull
        )))
        symbols.setPropertyType(randomAccessType, for: randomAccessSymbol)
    }

    /// Register `kotlin.collections.List<E>` interface stub with `operator fun get(index: Int): E`.
    func makeComparableTypeParam(
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner,
        memberFQName: [InternedString]
    ) -> (symbol: SymbolID, type: TypeID, upperBounds: [TypeID])? {
        guard let comparableSymbol = types.comparableInterfaceSymbol else {
            return nil
        }
        let rName = interner.intern("R")
        let rSymbol = symbols.define(
            kind: .typeParameter,
            name: rName,
            fqName: memberFQName + [rName],
            declSite: nil,
            visibility: .private,
            flags: []
        )
        let rType = types.make(.typeParam(TypeParamType(symbol: rSymbol, nullability: .nonNull)))
        let comparableRBounds: [TypeID] = [types.make(.classType(ClassType(
            classSymbol: comparableSymbol,
            args: [.in(rType)],
            nullability: .nonNull
        )))]
        return (rSymbol, rType, comparableRBounds)
    }

}
