// swiftlint:disable file_length

/// `List<E>.maxBy` / `minBy` / `maxOf` / `minOf` / `sumOf` / `count` /
/// `fold` / `reduce` and the comparator-based aggregate family
/// extracted from the KSP-697 list residual registry.
extension DataFlowSemaPhase {
    func registerListAggregateMembers(
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner,
        listFQName: [InternedString],
        listInterfaceSymbol: SymbolID,
        listTypeParamSymbol: SymbolID,
        listTypeParamType: TypeID,
        bundledIndex: BundledDeclarationIndex = .empty,
        skipStats: SyntheticStubSkipStatsCollector? = nil
    ) {
        let receiverType = types.make(.classType(ClassType(
            classSymbol: listInterfaceSymbol,
            args: [.out(listTypeParamType)],
            nullability: .nonNull
        )))

        func registerSimpleMember(
            name: String,
            returnType: TypeID,
            externalLinkName: String,
            canThrow: Bool = false
        ) {
            let memberName = interner.intern(name)
            let memberFQName = listFQName + [memberName]
            if BundledSyntheticStubRegistration.shouldSkipRegistration(
                declaredOwnerFQName: listFQName,
                receiverType: receiverType,
                name: memberName,
                arity: 0,
                symbols: symbols,
                types: types,
                interner: interner
            ) {
                return
            }
            guard symbols.lookup(fqName: memberFQName) == nil else { return }
            let memberSymbol = symbols.define(
                kind: .function,
                name: memberName,
                fqName: memberFQName,
                declSite: nil,
                visibility: .public,
                flags: [.synthetic]
            )
            symbols.setParentSymbol(listInterfaceSymbol, for: memberSymbol)
            symbols.setExternalLinkName(externalLinkName, for: memberSymbol)
            symbols.setFunctionSignature(
                FunctionSignature(
                    receiverType: receiverType,
                    parameterTypes: [],
                    returnType: returnType,
                    canThrow: canThrow,
                    typeParameterSymbols: [listTypeParamSymbol],
                    classTypeParameterCount: 1
                ),
                for: memberSymbol
            )
        }

        let nullableElementType = types.makeNullable(listTypeParamType)
        if types.comparableInterfaceSymbol == nil {
            registerSyntheticComparableStub(symbols: symbols, types: types, interner: interner)
            registerSyntheticComparableStub(
                symbols: symbols,
                types: types,
                interner: interner
            )
        }
        let comparableElementBounds: [TypeID] = if let comparableSymbol = types.comparableInterfaceSymbol {
            [types.make(.classType(ClassType(
                classSymbol: comparableSymbol,
                args: [.invariant(listTypeParamType)],
                nullability: .nonNull
            )))]
        } else {
            []
        }

        func registerComparableMember(
            name: String,
            externalLinkName: String,
            returnType: TypeID = nullableElementType
        ) {
            let memberName = interner.intern(name)
            let memberFQName = listFQName + [memberName]
            if BundledSyntheticStubRegistration.shouldSkipRegistration(
                declaredOwnerFQName: listFQName,
                receiverType: receiverType,
                name: memberName,
                arity: 0,
                symbols: symbols,
                types: types,
                interner: interner
            ) {
                return
            }
            guard symbols.lookup(fqName: memberFQName) == nil else { return }
            let memberSymbol = symbols.define(
                kind: .function,
                name: memberName,
                fqName: memberFQName,
                declSite: nil,
                visibility: .public,
                flags: [.synthetic]
            )
            symbols.setParentSymbol(listInterfaceSymbol, for: memberSymbol)
            symbols.setExternalLinkName(externalLinkName, for: memberSymbol)
            symbols.setFunctionSignature(
                FunctionSignature(
                    receiverType: receiverType,
                    parameterTypes: [],
                    returnType: returnType,
                    typeParameterSymbols: [listTypeParamSymbol],
                    typeParameterUpperBoundsList: [comparableElementBounds],
                    classTypeParameterCount: 1
                ),
                for: memberSymbol
            )
        }

        registerComparableMember(
            name: "max",
            externalLinkName: "kk_list_max",
            returnType: listTypeParamType
        )
        registerComparableMember(
            name: "min",
            externalLinkName: "kk_list_min",
            returnType: listTypeParamType
        )
        registerComparableMember(name: "maxOrNull", externalLinkName: "kk_list_maxOrNull")
        registerComparableMember(name: "minOrNull", externalLinkName: "kk_list_minOrNull")

        // maxByOrNull / minByOrNull / maxOfOrNull / minOfOrNull (STDLIB-301)
        do {
            func registerByOrNull(
                name: String,
                externalLinkName: String,
                returnTypeBuilder: (TypeID) -> TypeID
            ) {
                let memberName = interner.intern(name)
                let memberFQName = listFQName + [memberName]
                let shouldSkipMember: Bool
                if let contextTypes = BundledSyntheticStubRegistration.types {
                    shouldSkipMember = BundledSyntheticStubRegistration.shouldSkipRegistration(
                        declaredOwnerFQName: listFQName,
                        receiverType: receiverType,
                        name: memberName,
                        arity: 1,
                        symbols: symbols,
                        types: contextTypes,
                        interner: interner
                    )
                } else {
                    shouldSkipMember = shouldSkipSyntheticStub(
                        bundledIndex: bundledIndex,
                        ownerFQName: listFQName,
                        name: memberName,
                        arity: 1
                    )
                }
                if shouldSkipMember {
                    skipStats?.recordSkip(
                        ownerFQName: listFQName,
                        name: memberName,
                        arity: 1,
                        interner: interner
                    )
                    return
                }
                guard symbols.lookup(fqName: memberFQName) == nil else { return }

                let selectorReturnType: TypeID
                let extraTypeParamSymbols: [SymbolID]
                let extraUpperBoundsList: [[TypeID]]
                if let rParam = makeComparableTypeParam(
                    symbols: symbols, types: types, interner: interner,
                    memberFQName: memberFQName
                ) {
                    selectorReturnType = rParam.type
                    extraTypeParamSymbols = [rParam.symbol]
                    extraUpperBoundsList = [rParam.upperBounds]
                } else {
                    // Comparable unavailable – fall back to (E) -> Any selector
                    selectorReturnType = types.anyType
                    extraTypeParamSymbols = []
                    extraUpperBoundsList = []
                }
                let returnType = returnTypeBuilder(selectorReturnType)
                let selectorType = types.make(.functionType(FunctionType(
                    params: [listTypeParamType],
                    returnType: selectorReturnType,
                    isSuspend: false,
                    nullability: .nonNull
                )))
                let memberSymbol = symbols.define(
                    kind: .function,
                    name: memberName,
                    fqName: memberFQName,
                    declSite: nil,
                    visibility: .public,
                    flags: [.synthetic, .inlineFunction]
                )
                symbols.setParentSymbol(listInterfaceSymbol, for: memberSymbol)
                symbols.setExternalLinkName(externalLinkName, for: memberSymbol)
                symbols.setFunctionSignature(
                    FunctionSignature(
                        receiverType: receiverType,
                        parameterTypes: [selectorType],
                        returnType: returnType,
                        typeParameterSymbols: [listTypeParamSymbol] + extraTypeParamSymbols,
                        typeParameterUpperBoundsList: [[]] + extraUpperBoundsList,
                        classTypeParameterCount: 1
                    ),
                    for: memberSymbol
                )
            }

            registerByOrNull(
                name: "maxBy",
                externalLinkName: "kk_list_maxBy",
                returnTypeBuilder: { _ in listTypeParamType }
            )
            registerByOrNull(
                name: "maxByOrNull",
                externalLinkName: "kk_list_maxByOrNull",
                returnTypeBuilder: { _ in nullableElementType }
            )
            registerByOrNull(
                name: "minByOrNull",
                externalLinkName: "kk_list_minByOrNull",
                returnTypeBuilder: { _ in nullableElementType }
            )
            registerByOrNull(
                name: "minBy",
                externalLinkName: "kk_list_minBy",
                returnTypeBuilder: { _ in listTypeParamType }
            )
            registerByOrNull(
                name: "maxOfOrNull",
                externalLinkName: "kk_list_maxOfOrNull",
                returnTypeBuilder: { selectorResultType in types.makeNullable(selectorResultType) }
            )
            registerByOrNull(
                name: "minOfOrNull",
                externalLinkName: "kk_list_minOfOrNull",
                returnTypeBuilder: { selectorResultType in types.makeNullable(selectorResultType) }
            )

            // maxOf / minOf (non-OrNull, throws on empty) (STDLIB-301b)
            registerByOrNull(
                name: "maxOf",
                externalLinkName: "kk_list_maxOf",
                returnTypeBuilder: { selectorResultType in selectorResultType }
            )
            registerByOrNull(
                name: "minOf",
                externalLinkName: "kk_list_minOf",
                returnTypeBuilder: { selectorResultType in selectorResultType }
            )
        }

        // maxWith / maxWithOrNull / minWith / minWithOrNull (comparator-based) (STDLIB-301c)
        do {
            let comparatorType = if let comparatorSymbol = symbols.lookupByShortName(interner.intern("Comparator")).first {
                types.make(.classType(ClassType(
                    classSymbol: comparatorSymbol,
                    args: [.invariant(listTypeParamType)],
                    nullability: .nonNull
                )))
            } else {
                types.make(.functionType(FunctionType(
                    params: [listTypeParamType, listTypeParamType],
                    returnType: types.intType,
                    isSuspend: false,
                    nullability: .nonNull
                )))
            }

            func registerWithComparator(
                name: String,
                externalLinkName: String,
                returnType: TypeID
            ) {
                let memberName = interner.intern(name)
                let memberFQName = listFQName + [memberName]
                if BundledSyntheticStubRegistration.shouldSkipRegistration(
                    declaredOwnerFQName: listFQName,
                    receiverType: receiverType,
                    name: memberName,
                    arity: 1,
                    symbols: symbols,
                    types: types,
                    interner: interner
                ) { return }
                guard symbols.lookup(fqName: memberFQName) == nil else { return }
                let memberSymbol = symbols.define(
                    kind: .function,
                    name: memberName,
                    fqName: memberFQName,
                    declSite: nil,
                    visibility: .public,
                    flags: [.synthetic, .inlineFunction]
                )
                symbols.setParentSymbol(listInterfaceSymbol, for: memberSymbol)
                symbols.setExternalLinkName(externalLinkName, for: memberSymbol)
                symbols.setFunctionSignature(
                    FunctionSignature(
                        receiverType: receiverType,
                        parameterTypes: [comparatorType],
                        returnType: returnType,
                        typeParameterSymbols: [listTypeParamSymbol],
                        classTypeParameterCount: 1
                    ),
                    for: memberSymbol
                )
            }

            registerWithComparator(name: "maxWith", externalLinkName: "kk_list_maxWith", returnType: listTypeParamType)
            registerWithComparator(name: "maxWithOrNull", externalLinkName: "kk_list_maxWithOrNull", returnType: nullableElementType)
            registerWithComparator(name: "minWith", externalLinkName: "kk_list_minWith", returnType: listTypeParamType)
            registerWithComparator(name: "minWithOrNull", externalLinkName: "kk_list_minWithOrNull", returnType: nullableElementType)
        }

        // maxOfWith / maxOfWithOrNull / minOfWith / minOfWithOrNull (comparator + selector) (STDLIB-301d)
        do {
            func registerOfWithComparator(
                name: String,
                externalLinkName: String,
                returnTypeBuilder: (TypeID) -> TypeID
            ) {
                let memberName = interner.intern(name)
                let memberFQName = listFQName + [memberName]
                if BundledSyntheticStubRegistration.shouldSkipRegistration(
                    declaredOwnerFQName: listFQName,
                    receiverType: receiverType,
                    name: memberName,
                    arity: 2,
                    symbols: symbols,
                    types: types,
                    interner: interner
                ) { return }
                guard symbols.lookup(fqName: memberFQName) == nil else { return }

                // Introduce a type parameter R (no Comparable bound needed – the comparator handles ordering)
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

                let comparatorType = if let comparatorSymbol = symbols.lookupByShortName(interner.intern("Comparator")).first {
                    types.make(.classType(ClassType(
                        classSymbol: comparatorSymbol,
                        args: [.invariant(rType)],
                        nullability: .nonNull
                    )))
                } else {
                    types.make(.functionType(FunctionType(
                        params: [rType, rType],
                        returnType: types.intType,
                        isSuspend: false,
                        nullability: .nonNull
                    )))
                }
                let selectorType = types.make(.functionType(FunctionType(
                    params: [listTypeParamType],
                    returnType: rType,
                    isSuspend: false,
                    nullability: .nonNull
                )))
                let returnType = returnTypeBuilder(rType)
                let memberSymbol = symbols.define(
                    kind: .function,
                    name: memberName,
                    fqName: memberFQName,
                    declSite: nil,
                    visibility: .public,
                    flags: [.synthetic, .inlineFunction]
                )
                symbols.setParentSymbol(listInterfaceSymbol, for: memberSymbol)
                symbols.setExternalLinkName(externalLinkName, for: memberSymbol)
                symbols.setFunctionSignature(
                    FunctionSignature(
                        receiverType: receiverType,
                        parameterTypes: [comparatorType, selectorType],
                        returnType: returnType,
                        typeParameterSymbols: [listTypeParamSymbol, rSymbol],
                        typeParameterUpperBoundsList: [[], []],
                        classTypeParameterCount: 1
                    ),
                    for: memberSymbol
                )
            }

            registerOfWithComparator(
                name: "maxOfWith",
                externalLinkName: "kk_list_maxOfWith",
                returnTypeBuilder: { rType in rType }
            )
            registerOfWithComparator(
                name: "maxOfWithOrNull",
                externalLinkName: "kk_list_maxOfWithOrNull",
                returnTypeBuilder: { rType in types.makeNullable(rType) }
            )
            registerOfWithComparator(
                name: "minOfWith",
                externalLinkName: "kk_list_minOfWith",
                returnTypeBuilder: { rType in rType }
            )
            registerOfWithComparator(
                name: "minOfWithOrNull",
                externalLinkName: "kk_list_minOfWithOrNull",
                returnTypeBuilder: { rType in types.makeNullable(rType) }
            )
        }

        // random / randomOrNull (STDLIB-166)
        registerSimpleMember(name: "random", returnType: listTypeParamType, externalLinkName: "kk_list_random")
        registerSimpleMember(name: "randomOrNull", returnType: nullableElementType, externalLinkName: "kk_list_randomOrNull")

        // getOrNull / getOrElse / elementAt / elementAtOrNull / elementAtOrElse are
        // intentionally NOT registered as synthetic members here (KSP-424).
        // ListAccessHOF.kt declares all five on List<T>, and the kk_list_* bridges
        // they used to link against no longer exist in Sources/Runtime.

        // firstOrNull / lastOrNull / single / singleOrNull are intentionally NOT
        // registered as synthetic members here. ListSearchHOF.kt already declares
        // both the no-predicate and predicate overloads for each; a synthetic
        // arity-0 entry at these FQ names makes collectMemberFunctionCandidates
        // return a single arity-0 match and skip the extension-function scope
        // lookup that would otherwise find both Kotlin-source overloads,
        // permanently hiding the predicate overload.

        let sumOfName = interner.intern("sumOf")
        let sumOfFQName = listFQName + [sumOfName]
        let shouldSkipSumOf: Bool
        if let contextTypes = BundledSyntheticStubRegistration.types {
            shouldSkipSumOf = BundledSyntheticStubRegistration.shouldSkipRegistration(
                declaredOwnerFQName: listFQName,
                receiverType: receiverType,
                name: sumOfName,
                arity: 1,
                symbols: symbols,
                types: contextTypes,
                interner: interner
            )
        } else {
            shouldSkipSumOf = shouldSkipSyntheticStub(
                bundledIndex: bundledIndex,
                ownerFQName: listFQName,
                name: sumOfName,
                arity: 1
            )
        }
        if shouldSkipSumOf {
            skipStats?.recordSkip(
                ownerFQName: listFQName,
                name: sumOfName,
                arity: 1,
                interner: interner
            )
        } else if symbols.lookup(fqName: sumOfFQName) == nil {
            let transformType = types.make(.functionType(FunctionType(
                params: [listTypeParamType],
                returnType: types.intType,
                isSuspend: false,
                nullability: .nonNull
            )))
            let memberSymbol = symbols.define(
                kind: .function,
                name: sumOfName,
                fqName: sumOfFQName,
                declSite: nil,
                visibility: .public,
                flags: [.synthetic, .inlineFunction]
            )
            symbols.setParentSymbol(listInterfaceSymbol, for: memberSymbol)
            symbols.setExternalLinkName("sumOf", for: memberSymbol)
            symbols.setFunctionSignature(
                FunctionSignature(
                    receiverType: receiverType,
                    parameterTypes: [transformType],
                    returnType: types.intType,
                    typeParameterSymbols: [listTypeParamSymbol],
                    classTypeParameterCount: 1
                ),
                for: memberSymbol
            )
        }

        // Stdlib/kotlin/collections/ListSortOrdering.kt (MIGRATION-COL-006)
        // but is not yet wired into the compiler pipeline (RF-STDLIB-004+). Keep these stubs until then.
        // sortedByDescending (HOF, selector lambda with R: Comparable<R>)
        let sortedByDescendingName = interner.intern("sortedByDescending")
        let sortedByDescendingFQName = listFQName + [sortedByDescendingName]
        if let types = BundledSyntheticStubRegistration.types,
           !BundledSyntheticStubRegistration.shouldSkipRegistration(
               declaredOwnerFQName: listFQName,
               receiverType: receiverType,
               name: sortedByDescendingName,
               arity: 1,
               symbols: symbols,
               types: types,
               interner: interner
           ),
           symbols.lookup(fqName: sortedByDescendingFQName) == nil
        {
            let selectorReturnType: TypeID
            let extraTypeParamSymbols: [SymbolID]
            let extraUpperBoundsList: [[TypeID]]
            if let rParam = makeComparableTypeParam(
                symbols: symbols, types: types, interner: interner,
                memberFQName: sortedByDescendingFQName
            ) {
                selectorReturnType = rParam.type
                extraTypeParamSymbols = [rParam.symbol]
                extraUpperBoundsList = [rParam.upperBounds]
            } else {
                selectorReturnType = types.anyType
                extraTypeParamSymbols = []
                extraUpperBoundsList = []
            }
            let selectorType = types.make(.functionType(FunctionType(
                params: [listTypeParamType],
                returnType: selectorReturnType,
                isSuspend: false,
                nullability: .nonNull
            )))
            let memberSymbol = symbols.define(
                kind: .function,
                name: sortedByDescendingName,
                fqName: sortedByDescendingFQName,
                declSite: nil,
                visibility: .public,
                flags: [.synthetic, .inlineFunction]
            )
            symbols.setParentSymbol(listInterfaceSymbol, for: memberSymbol)
            symbols.setExternalLinkName("kk_list_sortedByDescending", for: memberSymbol)
            symbols.setFunctionSignature(
                FunctionSignature(
                    receiverType: receiverType,
                    parameterTypes: [selectorType],
                    returnType: receiverType,
                    typeParameterSymbols: [listTypeParamSymbol] + extraTypeParamSymbols,
                    typeParameterUpperBoundsList: [[]] + extraUpperBoundsList,
                    classTypeParameterCount: 1
                ),
                for: memberSymbol
            )
        }

        // sortedWith (HOF, comparator lambda with 2 args)
        let sortedWithName = interner.intern("sortedWith")
        let sortedWithFQName = listFQName + [sortedWithName]
        if let types = BundledSyntheticStubRegistration.types,
           !BundledSyntheticStubRegistration.shouldSkipRegistration(
               declaredOwnerFQName: listFQName,
               receiverType: receiverType,
               name: sortedWithName,
               arity: 1,
               symbols: symbols,
               types: types,
               interner: interner
           ),
           symbols.lookup(fqName: sortedWithFQName) == nil
        {
            let comparatorType = types.make(.functionType(FunctionType(
                params: [listTypeParamType, listTypeParamType],
                returnType: types.intType,
                isSuspend: false,
                nullability: .nonNull
            )))
            let memberSymbol = symbols.define(
                kind: .function,
                name: sortedWithName,
                fqName: sortedWithFQName,
                declSite: nil,
                visibility: .public,
                flags: [.synthetic, .inlineFunction]
            )
            symbols.setParentSymbol(listInterfaceSymbol, for: memberSymbol)
            symbols.setExternalLinkName("kk_list_sortedWith", for: memberSymbol)
            symbols.setFunctionSignature(
                FunctionSignature(
                    receiverType: receiverType,
                    parameterTypes: [comparatorType],
                    returnType: receiverType,
                    typeParameterSymbols: [listTypeParamSymbol],
                    classTypeParameterCount: 1
                ),
                for: memberSymbol
            )
        }

        // partition (HOF, predicate lambda)
        let partitionName = interner.intern("partition")
        let partitionFQName = listFQName + [partitionName]
        let shouldSkipPartition = BundledSyntheticStubRegistration.shouldSkipRegistration(
            declaredOwnerFQName: listFQName,
            receiverType: receiverType,
            name: partitionName,
            arity: 1,
            symbols: symbols,
            types: types,
            interner: interner
        )
        if !shouldSkipPartition, symbols.lookup(fqName: partitionFQName) == nil {
            let predicateType2 = types.make(.functionType(FunctionType(
                params: [listTypeParamType],
                returnType: types.booleanType,
                isSuspend: false,
                nullability: .nonNull
            )))
            let memberSymbol = symbols.define(
                kind: .function,
                name: partitionName,
                fqName: partitionFQName,
                declSite: nil,
                visibility: .public,
                flags: [.synthetic, .inlineFunction]
            )
            symbols.setParentSymbol(listInterfaceSymbol, for: memberSymbol)
            // Return type is Pair<List<T>, List<T>>
            let partitionReturnType: TypeID
            if let pairSymbol = symbols.lookup(fqName: [interner.intern("kotlin"), interner.intern("Pair")]) {
                let listOfE = types.make(.classType(ClassType(
                    classSymbol: listInterfaceSymbol,
                    args: [.out(listTypeParamType)],
                    nullability: .nonNull
                )))
                partitionReturnType = types.make(.classType(ClassType(
                    classSymbol: pairSymbol,
                    args: [.out(listOfE), .out(listOfE)],
                    nullability: .nonNull
                )))
            } else {
                partitionReturnType = types.anyType
            }
            symbols.setFunctionSignature(
                FunctionSignature(
                    receiverType: receiverType,
                    parameterTypes: [predicateType2],
                    returnType: partitionReturnType,
                    typeParameterSymbols: [listTypeParamSymbol],
                    classTypeParameterCount: 1
                ),
                for: memberSymbol
            )
        }

        // zip(other: Iterable<R>): List<Pair<E, R>>
        let zipName = interner.intern("zip")
        let zipFQName = listFQName + [zipName]
        let collectionsFQName = Array(listFQName.dropLast())
        let iterableFQName = collectionsFQName + [interner.intern("Iterable")]
        let sourceBackedZipOneArg = bundledIndex.contains(ownerFQName: iterableFQName, name: zipName, arity: 1)
            || BundledSyntheticStubRegistration.bundledIndex.contains(
                ownerFQName: iterableFQName,
                name: zipName,
                arity: 1
            )
        if !sourceBackedZipOneArg, symbols.lookup(fqName: zipFQName) == nil {
            let rName = interner.intern("R")
            let rSymbol = symbols.define(
                kind: .typeParameter,
                name: rName,
                fqName: zipFQName + [rName],
                declSite: nil,
                visibility: .private,
                flags: []
            )
            let rType = types.make(.typeParam(TypeParamType(symbol: rSymbol, nullability: .nonNull)))
            let otherListType = types.make(.classType(ClassType(
                classSymbol: listInterfaceSymbol,
                args: [.out(rType)],
                nullability: .nonNull
            )))
            let pairType: TypeID
            if let pairSymbol = symbols.lookup(fqName: [interner.intern("kotlin"), interner.intern("Pair")])
                ?? symbols.lookupByShortName(interner.intern("Pair")).first
            {
                pairType = types.make(.classType(ClassType(
                    classSymbol: pairSymbol,
                    args: [.out(listTypeParamType), .out(rType)],
                    nullability: .nonNull
                )))
            } else {
                pairType = types.anyType
            }
            let zippedListType = types.make(.classType(ClassType(
                classSymbol: listInterfaceSymbol,
                args: [.out(pairType)],
                nullability: .nonNull
            )))
            let memberSymbol = symbols.define(
                kind: .function,
                name: zipName,
                fqName: zipFQName,
                declSite: nil,
                visibility: .public,
                flags: [.synthetic]
            )
            symbols.setParentSymbol(listInterfaceSymbol, for: memberSymbol)
            symbols.setExternalLinkName("kk_list_zip", for: memberSymbol)
            symbols.setFunctionSignature(
                FunctionSignature(
                    receiverType: receiverType,
                    parameterTypes: [otherListType],
                    returnType: zippedListType,
                    typeParameterSymbols: [listTypeParamSymbol, rSymbol],
                    classTypeParameterCount: 1
                ),
                for: memberSymbol
            )
        }

        // zip(other: Iterable<R>, transform: (E, R) -> V): List<V>
        let existingZipOverloads = symbols.lookupAll(fqName: zipFQName)
        let hasTwoParamZip = existingZipOverloads.contains { symID in
            guard let sig = symbols.functionSignature(for: symID) else { return false }
            return sig.parameterTypes.count == 2
        }
        let sourceBackedZipTransform = bundledIndex.contains(ownerFQName: iterableFQName, name: zipName, arity: 2)
            || BundledSyntheticStubRegistration.bundledIndex.contains(
                ownerFQName: iterableFQName,
                name: zipName,
                arity: 2
            )
        if !sourceBackedZipTransform, !hasTwoParamZip {
            let zipTransformScope = zipFQName + [interner.intern("transform")]
            let otherRName = interner.intern("R")
            let otherRSymbol = symbols.define(
                kind: .typeParameter,
                name: otherRName,
                fqName: zipTransformScope + [otherRName],
                declSite: nil,
                visibility: .private,
                flags: []
            )
            let otherRType = types.make(.typeParam(TypeParamType(symbol: otherRSymbol, nullability: .nonNull)))
            let otherListTypeForTransform = types.make(.classType(ClassType(
                classSymbol: listInterfaceSymbol,
                args: [.out(otherRType)],
                nullability: .nonNull
            )))
            let vName = interner.intern("V")
            let vSymbol = symbols.define(
                kind: .typeParameter,
                name: vName,
                fqName: zipTransformScope + [vName],
                declSite: nil,
                visibility: .private,
                flags: []
            )
            let vType = types.make(.typeParam(TypeParamType(symbol: vSymbol, nullability: .nonNull)))
            let transformFnType = types.make(.functionType(FunctionType(
                params: [listTypeParamType, otherRType],
                returnType: vType,
                isSuspend: false,
                nullability: .nonNull
            )))
            let transformResultListType = types.make(.classType(ClassType(
                classSymbol: listInterfaceSymbol,
                args: [.out(vType)],
                nullability: .nonNull
            )))
            let transformMemberSymbol = symbols.define(
                kind: .function,
                name: zipName,
                fqName: zipFQName,
                declSite: nil,
                visibility: .public,
                flags: [.synthetic, .inlineFunction]
            )
            symbols.setParentSymbol(listInterfaceSymbol, for: transformMemberSymbol)
            symbols.setExternalLinkName("kk_list_zip_transform", for: transformMemberSymbol)
            symbols.setFunctionSignature(
                FunctionSignature(
                    receiverType: receiverType,
                    parameterTypes: [otherListTypeForTransform, transformFnType],
                    returnType: transformResultListType,
                    typeParameterSymbols: [listTypeParamSymbol, otherRSymbol, vSymbol],
                    classTypeParameterCount: 1
                ),
                for: transformMemberSymbol
            )
        }

        // unzip(): Pair<List<A>, List<B>> for List<Pair<A, B>>
        let unzipName = interner.intern("unzip")
        let unzipFQName = listFQName + [unzipName]
        let shouldSkipUnzip = BundledSyntheticStubRegistration.shouldSkipRegistration(
            declaredOwnerFQName: listFQName,
            receiverType: receiverType,
            name: unzipName,
            arity: 0,
            symbols: symbols,
            types: types,
            interner: interner
        )
        if !shouldSkipUnzip, symbols.lookup(fqName: unzipFQName) == nil {
            let aName = interner.intern("A")
            let aSymbol = symbols.define(
                kind: .typeParameter,
                name: aName,
                fqName: unzipFQName + [aName],
                declSite: nil,
                visibility: .private,
                flags: []
            )
            let bName = interner.intern("B")
            let bSymbol = symbols.define(
                kind: .typeParameter,
                name: bName,
                fqName: unzipFQName + [bName],
                declSite: nil,
                visibility: .private,
                flags: []
            )
            let aType = types.make(.typeParam(TypeParamType(symbol: aSymbol, nullability: .nonNull)))
            let bType = types.make(.typeParam(TypeParamType(symbol: bSymbol, nullability: .nonNull)))
            let pairSymbol = symbols.lookup(fqName: [interner.intern("kotlin"), interner.intern("Pair")])
                ?? symbols.lookupByShortName(interner.intern("Pair")).first
            let specializedReceiverType: TypeID
            let returnType: TypeID
            if let pairSymbol {
                let pairElementType = types.make(.classType(ClassType(
                    classSymbol: pairSymbol,
                    args: [.out(aType), .out(bType)],
                    nullability: .nonNull
                )))
                specializedReceiverType = types.make(.classType(ClassType(
                    classSymbol: listInterfaceSymbol,
                    args: [.out(pairElementType)],
                    nullability: .nonNull
                )))
                let firstListType = types.make(.classType(ClassType(
                    classSymbol: listInterfaceSymbol,
                    args: [.out(aType)],
                    nullability: .nonNull
                )))
                let secondListType = types.make(.classType(ClassType(
                    classSymbol: listInterfaceSymbol,
                    args: [.out(bType)],
                    nullability: .nonNull
                )))
                returnType = types.make(.classType(ClassType(
                    classSymbol: pairSymbol,
                    args: [.out(firstListType), .out(secondListType)],
                    nullability: .nonNull
                )))
            } else {
                specializedReceiverType = receiverType
                returnType = types.anyType
            }
            let memberSymbol = symbols.define(
                kind: .function,
                name: unzipName,
                fqName: unzipFQName,
                declSite: nil,
                visibility: .public,
                flags: [.synthetic]
            )
            symbols.setParentSymbol(listInterfaceSymbol, for: memberSymbol)
            symbols.setFunctionSignature(
                FunctionSignature(
                    receiverType: specializedReceiverType,
                    parameterTypes: [],
                    returnType: returnType,
                    typeParameterSymbols: [aSymbol, bSymbol],
                    classTypeParameterCount: 0
                ),
                for: memberSymbol
            )
        }

    }
}
