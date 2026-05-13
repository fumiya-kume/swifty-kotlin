// swiftlint:disable file_length

/// `List<E>.maxBy` / `minBy` / `maxOf` / `minOf` / `sumOf` / `count` /
/// `fold` / `reduce` and the comparator-based aggregate family
/// extracted from `HeaderHelpers+SyntheticListStubs.swift`.
extension DataFlowSemaPhase {
    func registerListAggregateMembers(
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner,
        listFQName: [InternedString],
        listInterfaceSymbol: SymbolID,
        listTypeParamSymbol: SymbolID,
        listTypeParamType: TypeID
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

        // getOrNull / elementAtOrNull / getOrElse (STDLIB-212)
        do {
            let getOrNullName = interner.intern("getOrNull")
            let getOrNullFQName = listFQName + [getOrNullName]
            if symbols.lookup(fqName: getOrNullFQName) == nil {
                let memberSymbol = symbols.define(
                    kind: .function,
                    name: getOrNullName,
                    fqName: getOrNullFQName,
                    declSite: nil,
                    visibility: .public,
                    flags: [.synthetic]
                )
                symbols.setParentSymbol(listInterfaceSymbol, for: memberSymbol)
                symbols.setExternalLinkName("kk_list_getOrNull", for: memberSymbol)
                symbols.setFunctionSignature(
                    FunctionSignature(
                        receiverType: receiverType,
                        parameterTypes: [types.intType],
                        returnType: nullableElementType,
                        typeParameterSymbols: [listTypeParamSymbol],
                        classTypeParameterCount: 1
                    ),
                    for: memberSymbol
                )
            }

            let elementAtOrNullName = interner.intern("elementAtOrNull")
            let elementAtOrNullFQName = listFQName + [elementAtOrNullName]
            if symbols.lookup(fqName: elementAtOrNullFQName) == nil {
                let memberSymbol = symbols.define(
                    kind: .function,
                    name: elementAtOrNullName,
                    fqName: elementAtOrNullFQName,
                    declSite: nil,
                    visibility: .public,
                    flags: [.synthetic]
                )
                symbols.setParentSymbol(listInterfaceSymbol, for: memberSymbol)
                symbols.setExternalLinkName("kk_list_elementAtOrNull", for: memberSymbol)
                symbols.setFunctionSignature(
                    FunctionSignature(
                        receiverType: receiverType,
                        parameterTypes: [types.intType],
                        returnType: nullableElementType,
                        typeParameterSymbols: [listTypeParamSymbol],
                        classTypeParameterCount: 1
                    ),
                    for: memberSymbol
                )
            }

            let getOrElseLambdaType = types.make(.functionType(FunctionType(
                params: [types.intType],
                returnType: listTypeParamType,
                isSuspend: false,
                nullability: .nonNull
            )))
            let getOrElseName = interner.intern("getOrElse")
            let getOrElseFQName = listFQName + [getOrElseName]
            if symbols.lookup(fqName: getOrElseFQName) == nil {
                let memberSymbol = symbols.define(
                    kind: .function,
                    name: getOrElseName,
                    fqName: getOrElseFQName,
                    declSite: nil,
                    visibility: .public,
                    flags: [.synthetic, .inlineFunction]
                )
                symbols.setParentSymbol(listInterfaceSymbol, for: memberSymbol)
                symbols.setExternalLinkName("kk_list_getOrElse", for: memberSymbol)
                symbols.setFunctionSignature(
                    FunctionSignature(
                        receiverType: receiverType,
                        parameterTypes: [types.intType, getOrElseLambdaType],
                        returnType: listTypeParamType,
                        typeParameterSymbols: [listTypeParamSymbol],
                        classTypeParameterCount: 1
                    ),
                    for: memberSymbol
                )
            }

            // elementAtOrElse — identical signature to getOrElse (STDLIB-212)
            let elementAtOrElseName = interner.intern("elementAtOrElse")
            let elementAtOrElseFQName = listFQName + [elementAtOrElseName]
            if symbols.lookup(fqName: elementAtOrElseFQName) == nil {
                let memberSymbol = symbols.define(
                    kind: .function,
                    name: elementAtOrElseName,
                    fqName: elementAtOrElseFQName,
                    declSite: nil,
                    visibility: .public,
                    flags: [.synthetic, .inlineFunction]
                )
                symbols.setParentSymbol(listInterfaceSymbol, for: memberSymbol)
                symbols.setExternalLinkName("kk_list_elementAtOrElse", for: memberSymbol)
                symbols.setFunctionSignature(
                    FunctionSignature(
                        receiverType: receiverType,
                        parameterTypes: [types.intType, getOrElseLambdaType],
                        returnType: listTypeParamType,
                        typeParameterSymbols: [listTypeParamSymbol],
                        classTypeParameterCount: 1
                    ),
                    for: memberSymbol
                )
            }
        }

        // elementAt — throws IndexOutOfBoundsException (STDLIB-212)
        do {
            let elementAtName = interner.intern("elementAt")
            let elementAtFQName = listFQName + [elementAtName]
            if symbols.lookup(fqName: elementAtFQName) == nil {
                let memberSymbol = symbols.define(
                    kind: .function,
                    name: elementAtName,
                    fqName: elementAtFQName,
                    declSite: nil,
                    visibility: .public,
                    flags: [.synthetic]
                )
                symbols.setParentSymbol(listInterfaceSymbol, for: memberSymbol)
                symbols.setExternalLinkName("kk_list_elementAt", for: memberSymbol)
                symbols.setFunctionSignature(
                    FunctionSignature(
                        receiverType: receiverType,
                        parameterTypes: [types.intType],
                        returnType: listTypeParamType,
                        canThrow: true,
                        typeParameterSymbols: [listTypeParamSymbol],
                        classTypeParameterCount: 1
                    ),
                    for: memberSymbol
                )
            }
        }

        // firstOrNull / lastOrNull no-predicate (STDLIB-210)
        registerSimpleMember(name: "firstOrNull", returnType: nullableElementType, externalLinkName: "kk_list_firstOrNull")
        registerSimpleMember(name: "lastOrNull", returnType: nullableElementType, externalLinkName: "kk_list_lastOrNull")
        // single no-predicate (STDLIB-COL-FN-184)
        registerSimpleMember(name: "single", returnType: listTypeParamType, externalLinkName: "kk_list_single", canThrow: true)
        // singleOrNull no-predicate (STDLIB-211)
        registerSimpleMember(name: "singleOrNull", returnType: nullableElementType, externalLinkName: "kk_list_singleOrNull")

        // indexOf / lastIndexOf (non-HOF, element argument)
        let indexOfName = interner.intern("indexOf")
        let indexOfFQName = listFQName + [indexOfName]
        if symbols.lookup(fqName: indexOfFQName) == nil {
            let memberSymbol = symbols.define(
                kind: .function,
                name: indexOfName,
                fqName: indexOfFQName,
                declSite: nil,
                visibility: .public,
                flags: [.synthetic]
            )
            symbols.setParentSymbol(listInterfaceSymbol, for: memberSymbol)
            symbols.setExternalLinkName("kk_list_indexOf", for: memberSymbol)
            symbols.setFunctionSignature(
                FunctionSignature(
                    receiverType: receiverType,
                    parameterTypes: [listTypeParamType],
                    returnType: types.intType,
                    typeParameterSymbols: [listTypeParamSymbol],
                    classTypeParameterCount: 1
                ),
                for: memberSymbol
            )
        }

        let lastIndexOfName = interner.intern("lastIndexOf")
        let lastIndexOfFQName = listFQName + [lastIndexOfName]
        if symbols.lookup(fqName: lastIndexOfFQName) == nil {
            let memberSymbol = symbols.define(
                kind: .function,
                name: lastIndexOfName,
                fqName: lastIndexOfFQName,
                declSite: nil,
                visibility: .public,
                flags: [.synthetic]
            )
            symbols.setParentSymbol(listInterfaceSymbol, for: memberSymbol)
            symbols.setExternalLinkName("kk_list_lastIndexOf", for: memberSymbol)
            symbols.setFunctionSignature(
                FunctionSignature(
                    receiverType: receiverType,
                    parameterTypes: [listTypeParamType],
                    returnType: types.intType,
                    typeParameterSymbols: [listTypeParamSymbol],
                    classTypeParameterCount: 1
                ),
                for: memberSymbol
            )
        }

        // STDLIB-214: binarySearch(element) — non-HOF, element argument
        let binarySearchName = interner.intern("binarySearch")
        let binarySearchFQName = listFQName + [binarySearchName]
        if symbols.lookup(fqName: binarySearchFQName) == nil {
            let memberSymbol = symbols.define(
                kind: .function,
                name: binarySearchName,
                fqName: binarySearchFQName,
                declSite: nil,
                visibility: .public,
                flags: [.synthetic]
            )
            symbols.setParentSymbol(listInterfaceSymbol, for: memberSymbol)
            symbols.setExternalLinkName("kk_list_binarySearch", for: memberSymbol)
            symbols.setFunctionSignature(
                FunctionSignature(
                    receiverType: receiverType,
                    parameterTypes: [listTypeParamType],
                    returnType: types.intType,
                    typeParameterSymbols: [listTypeParamSymbol],
                    typeParameterUpperBoundsList: [comparableElementBounds],
                    classTypeParameterCount: 1
                ),
                for: memberSymbol
            )
        }

        func registerMemberOverload(
            memberName: InternedString,
            memberFQName: [InternedString],
            parameterTypes: [TypeID],
            externalLinkName: String,
            returnTypeOverride: TypeID? = nil,
            typeParameterSymbols: [SymbolID]? = nil,
            typeParameterUpperBoundsList: [[TypeID]]? = nil,
            flags: SymbolFlags = [.synthetic],
            reifiedTypeParameterIndices: Set<Int> = []
        ) {
            let alreadyRegistered = symbols.lookupAll(fqName: memberFQName).contains { symbolID in
                guard let sig = symbols.functionSignature(for: symbolID) else { return false }
                return sig.parameterTypes == parameterTypes
            }
            guard !alreadyRegistered else { return }
            let memberSymbol = symbols.define(
                kind: .function,
                name: memberName,
                fqName: memberFQName,
                declSite: nil,
                visibility: .public,
                flags: flags
            )
            symbols.setParentSymbol(listInterfaceSymbol, for: memberSymbol)
            symbols.setExternalLinkName(externalLinkName, for: memberSymbol)
            symbols.setFunctionSignature(
                FunctionSignature(
                    receiverType: receiverType,
                    parameterTypes: parameterTypes,
                    returnType: returnTypeOverride ?? receiverType,
                    typeParameterSymbols: typeParameterSymbols ?? [listTypeParamSymbol],
                    reifiedTypeParameterIndices: reifiedTypeParameterIndices,
                    typeParameterUpperBoundsList: typeParameterUpperBoundsList ?? [],
                    classTypeParameterCount: 1
                ),
                for: memberSymbol
            )
        }

        // STDLIB-COL-BSEARCH-001: binarySearchBy(key, fromIndex, toIndex, selector)
        // The Kotlin stdlib models the omitted fromIndex/toIndex values as defaults,
        // but this compiler keeps the resolution shape explicit with 2/3/4-argument
        // overloads so the lambda always stays in the final slot.
        let binarySearchByName = interner.intern("binarySearchBy")
        let binarySearchByFQName = listFQName + [binarySearchByName]
        let binarySearchByKeyTypeParamName = interner.intern("R")
        let binarySearchByKeyTypeParamFQName = binarySearchByFQName + [binarySearchByKeyTypeParamName]
        let binarySearchByKeyTypeParamSymbol = symbols.define(
            kind: .typeParameter,
            name: binarySearchByKeyTypeParamName,
            fqName: binarySearchByKeyTypeParamFQName,
            declSite: nil,
            visibility: .private,
            flags: []
        )
        let binarySearchByKeyTypeParamType = types.make(.typeParam(TypeParamType(
            symbol: binarySearchByKeyTypeParamSymbol,
            nullability: .nonNull
        )))
        let binarySearchByComparableBounds: [TypeID] = if let comparableSymbol = types.comparableInterfaceSymbol {
            [types.make(.classType(ClassType(
                classSymbol: comparableSymbol,
                args: [.invariant(binarySearchByKeyTypeParamType)],
                nullability: .nonNull
            )))]
        } else {
            []
        }
        let binarySearchByKeyType: TypeID
        let binarySearchByTypeParameterSymbols: [SymbolID]
        let binarySearchByTypeParameterUpperBoundsList: [[TypeID]]
        binarySearchByKeyType = types.makeNullable(binarySearchByKeyTypeParamType)
        binarySearchByTypeParameterSymbols = [listTypeParamSymbol, binarySearchByKeyTypeParamSymbol]
        binarySearchByTypeParameterUpperBoundsList = [[], binarySearchByComparableBounds]
        let binarySearchBySelectorType = types.make(.functionType(FunctionType(
            params: [listTypeParamType],
            returnType: binarySearchByKeyType,
            isSuspend: false,
            nullability: .nonNull
        )))
        registerMemberOverload(
            memberName: binarySearchByName,
            memberFQName: binarySearchByFQName,
            parameterTypes: [binarySearchByKeyType, binarySearchBySelectorType],
            externalLinkName: "kk_list_binarySearchBy",
            returnTypeOverride: types.intType,
            typeParameterSymbols: binarySearchByTypeParameterSymbols,
            typeParameterUpperBoundsList: binarySearchByTypeParameterUpperBoundsList,
            flags: [.synthetic, .inlineFunction]
        )
        registerMemberOverload(
            memberName: binarySearchByName,
            memberFQName: binarySearchByFQName,
            parameterTypes: [binarySearchByKeyType, types.intType, binarySearchBySelectorType],
            externalLinkName: "kk_list_binarySearchBy_fromIndex",
            returnTypeOverride: types.intType,
            typeParameterSymbols: binarySearchByTypeParameterSymbols,
            typeParameterUpperBoundsList: binarySearchByTypeParameterUpperBoundsList,
            flags: [.synthetic, .inlineFunction]
        )
        registerMemberOverload(
            memberName: binarySearchByName,
            memberFQName: binarySearchByFQName,
            parameterTypes: [binarySearchByKeyType, types.intType, types.intType, binarySearchBySelectorType],
            externalLinkName: "kk_list_binarySearchBy_range",
            returnTypeOverride: types.intType,
            typeParameterSymbols: binarySearchByTypeParameterSymbols,
            typeParameterUpperBoundsList: binarySearchByTypeParameterUpperBoundsList,
            flags: [.synthetic, .inlineFunction]
        )

        // STDLIB-547: binarySearch(comparison: (T) -> Int) — HOF, comparison lambda
        let binarySearchCompareName = interner.intern("binarySearch")
        // Use a distinct FQ name to differentiate from the element-based overload
        let binarySearchCompareFQName = listFQName + [interner.intern(binarySearchCompareFQSuffix)]
        if symbols.lookup(fqName: binarySearchCompareFQName) == nil {
            let comparisonType = types.make(.functionType(FunctionType(
                params: [listTypeParamType],
                returnType: types.intType,
                isSuspend: false,
                nullability: .nonNull
            )))
            let memberSymbol = symbols.define(
                kind: .function,
                name: binarySearchCompareName,
                fqName: binarySearchCompareFQName,
                declSite: nil,
                visibility: .public,
                flags: [.synthetic, .inlineFunction]
            )
            symbols.setParentSymbol(listInterfaceSymbol, for: memberSymbol)
            symbols.setExternalLinkName("kk_list_binarySearch_compare", for: memberSymbol)
            symbols.setFunctionSignature(
                FunctionSignature(
                    receiverType: receiverType,
                    parameterTypes: [comparisonType],
                    returnType: types.intType,
                    typeParameterSymbols: [listTypeParamSymbol],
                    classTypeParameterCount: 1
                ),
                for: memberSymbol
            )
        }

        // STDLIB-COL-BSEARCH-002: binarySearch(element, comparator, fromIndex, toIndex)
        // comparator object overload with defaulted search range.
        let binarySearchComparatorName = interner.intern("binarySearch")
        let binarySearchComparatorFQName = listFQName + [interner.intern(binarySearchComparatorFQSuffix)]
        if symbols.lookup(fqName: binarySearchComparatorFQName) == nil {
            let comparatorType: TypeID = if let comparatorSymbol = symbols.lookupByShortName(interner.intern("Comparator")).first {
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
            let memberSymbol = symbols.define(
                kind: .function,
                name: binarySearchComparatorName,
                fqName: binarySearchComparatorFQName,
                declSite: nil,
                visibility: .public,
                flags: [.synthetic, .inlineFunction]
            )
            symbols.setParentSymbol(listInterfaceSymbol, for: memberSymbol)
            symbols.setExternalLinkName("kk_list_binarySearch_comparator", for: memberSymbol)

            let parameterSpecs: [(name: String, type: TypeID, hasDefault: Bool)] = [
                ("element", listTypeParamType, false),
                ("comparator", comparatorType, false),
                ("fromIndex", types.intType, true),
                ("toIndex", types.intType, true),
            ]
            var parameterTypes: [TypeID] = []
            var parameterSymbols: [SymbolID] = []
            var parameterDefaults: [Bool] = []
            for parameter in parameterSpecs {
                let parameterName = interner.intern(parameter.name)
                let parameterSymbol = symbols.define(
                    kind: .valueParameter,
                    name: parameterName,
                    fqName: binarySearchComparatorFQName + [parameterName],
                    declSite: nil,
                    visibility: .private,
                    flags: [.synthetic]
                )
                symbols.setParentSymbol(memberSymbol, for: parameterSymbol)
                parameterTypes.append(parameter.type)
                parameterSymbols.append(parameterSymbol)
                parameterDefaults.append(parameter.hasDefault)
            }

            symbols.setFunctionSignature(
                FunctionSignature(
                    receiverType: receiverType,
                    parameterTypes: parameterTypes,
                    returnType: types.intType,
                    valueParameterSymbols: parameterSymbols,
                    valueParameterHasDefaultValues: parameterDefaults,
                    valueParameterIsVararg: Array(repeating: false, count: parameterSpecs.count),
                    typeParameterSymbols: [listTypeParamSymbol],
                    classTypeParameterCount: 1
                ),
                for: memberSymbol
            )
        }

        // indexOfFirst / indexOfLast (HOF, predicate lambda)
        let predicateType = types.make(.functionType(FunctionType(
            params: [listTypeParamType],
            returnType: types.booleanType,
            isSuspend: false,
            nullability: .nonNull
        )))

        let indexOfFirstName = interner.intern("indexOfFirst")
        let indexOfFirstFQName = listFQName + [indexOfFirstName]
        if symbols.lookup(fqName: indexOfFirstFQName) == nil {
            let memberSymbol = symbols.define(
                kind: .function,
                name: indexOfFirstName,
                fqName: indexOfFirstFQName,
                declSite: nil,
                visibility: .public,
                flags: [.synthetic, .inlineFunction]
            )
            symbols.setParentSymbol(listInterfaceSymbol, for: memberSymbol)
            symbols.setExternalLinkName("kk_list_indexOfFirst", for: memberSymbol)
            symbols.setFunctionSignature(
                FunctionSignature(
                    receiverType: receiverType,
                    parameterTypes: [predicateType],
                    returnType: types.intType,
                    typeParameterSymbols: [listTypeParamSymbol],
                    classTypeParameterCount: 1
                ),
                for: memberSymbol
            )
        }

        let indexOfLastName = interner.intern("indexOfLast")
        let indexOfLastFQName = listFQName + [indexOfLastName]
        if symbols.lookup(fqName: indexOfLastFQName) == nil {
            let memberSymbol = symbols.define(
                kind: .function,
                name: indexOfLastName,
                fqName: indexOfLastFQName,
                declSite: nil,
                visibility: .public,
                flags: [.synthetic, .inlineFunction]
            )
            symbols.setParentSymbol(listInterfaceSymbol, for: memberSymbol)
            symbols.setExternalLinkName("kk_list_indexOfLast", for: memberSymbol)
            symbols.setFunctionSignature(
                FunctionSignature(
                    receiverType: receiverType,
                    parameterTypes: [predicateType],
                    returnType: types.intType,
                    typeParameterSymbols: [listTypeParamSymbol],
                    classTypeParameterCount: 1
                ),
                for: memberSymbol
            )
        }

        // takeWhile / dropWhile / takeLastWhile / dropLastWhile (STDLIB-440)
        for (funcName, linkName, canThrow) in [
            ("takeWhile", "kk_list_takeWhile", true),
            ("dropWhile", "kk_list_dropWhile", false),
            ("takeLastWhile", "kk_list_takeLastWhile", false),
            ("dropLastWhile", "kk_list_dropLastWhile", false),
        ] {
            let name = interner.intern(funcName)
            let fqName = listFQName + [name]
            if symbols.lookup(fqName: fqName) == nil {
                let memberSymbol = symbols.define(
                    kind: .function,
                    name: name,
                    fqName: fqName,
                    declSite: nil,
                    visibility: .public,
                    flags: [.synthetic, .inlineFunction]
                )
                symbols.setParentSymbol(listInterfaceSymbol, for: memberSymbol)
                symbols.setExternalLinkName(linkName, for: memberSymbol)
                symbols.setFunctionSignature(
                    FunctionSignature(
                        receiverType: receiverType,
                        parameterTypes: [predicateType],
                        returnType: receiverType,
                        canThrow: canThrow,
                        typeParameterSymbols: [listTypeParamSymbol],
                        classTypeParameterCount: 1
                    ),
                    for: memberSymbol
                )
            }
        }

        let sumOfName = interner.intern("sumOf")
        let sumOfFQName = listFQName + [sumOfName]
        if symbols.lookup(fqName: sumOfFQName) == nil {
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
            symbols.setExternalLinkName("kk_list_sumOf", for: memberSymbol)
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

        // sortedByDescending (HOF, selector lambda with R: Comparable<R>)
        let sortedByDescendingName = interner.intern("sortedByDescending")
        let sortedByDescendingFQName = listFQName + [sortedByDescendingName]
        if symbols.lookup(fqName: sortedByDescendingFQName) == nil {
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
        if symbols.lookup(fqName: sortedWithFQName) == nil {
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
        if symbols.lookup(fqName: partitionFQName) == nil {
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
            symbols.setExternalLinkName("kk_list_partition", for: memberSymbol)
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
        if symbols.lookup(fqName: zipFQName) == nil {
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

        // unzip(): Pair<List<A>, List<B>> for List<Pair<A, B>>
        let unzipName = interner.intern("unzip")
        let unzipFQName = listFQName + [unzipName]
        if symbols.lookup(fqName: unzipFQName) == nil {
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
            symbols.setExternalLinkName("kk_list_unzip", for: memberSymbol)
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

        // zipWithNext(): List<Pair<T, T>>
        let zipWithNextName = interner.intern("zipWithNext")
        let zipWithNextFQName = listFQName + [zipWithNextName]
        if symbols.lookup(fqName: zipWithNextFQName) == nil {
            let pairType: TypeID
            if let pairSymbol = symbols.lookup(fqName: [interner.intern("kotlin"), interner.intern("Pair")])
                ?? symbols.lookupByShortName(interner.intern("Pair")).first
            {
                pairType = types.make(.classType(ClassType(
                    classSymbol: pairSymbol,
                    args: [.out(listTypeParamType), .out(listTypeParamType)],
                    nullability: .nonNull
                )))
            } else {
                pairType = types.anyType
            }
            let zipWithNextResultType = types.make(.classType(ClassType(
                classSymbol: listInterfaceSymbol,
                args: [.out(pairType)],
                nullability: .nonNull
            )))
            let memberSymbol = symbols.define(
                kind: .function,
                name: zipWithNextName,
                fqName: zipWithNextFQName,
                declSite: nil,
                visibility: .public,
                flags: [.synthetic]
            )
            symbols.setParentSymbol(listInterfaceSymbol, for: memberSymbol)
            symbols.setExternalLinkName("kk_list_zipWithNext", for: memberSymbol)
            symbols.setFunctionSignature(
                FunctionSignature(
                    receiverType: receiverType,
                    parameterTypes: [],
                    returnType: zipWithNextResultType,
                    typeParameterSymbols: [listTypeParamSymbol],
                    classTypeParameterCount: 1
                ),
                for: memberSymbol
            )
        }

        let zipWithNextTransformFQName = listFQName + [zipWithNextName]
        let existingZipWithNextOverloads = symbols.lookupAll(fqName: zipWithNextTransformFQName)
        let hasZipWithNextTransform = existingZipWithNextOverloads.contains { symID in
            guard let sig = symbols.functionSignature(for: symID) else { return false }
            return sig.parameterTypes.count == 1
        }
        if !hasZipWithNextTransform {
            let rName = interner.intern("R")
            let rSymbol = symbols.define(
                kind: .typeParameter,
                name: rName,
                fqName: zipWithNextTransformFQName + [rName],
                declSite: nil,
                visibility: .private,
                flags: []
            )
            let rType = types.make(.typeParam(TypeParamType(symbol: rSymbol, nullability: .nonNull)))
            let transformFnType = types.make(.functionType(FunctionType(
                params: [listTypeParamType, listTypeParamType],
                returnType: rType,
                isSuspend: false,
                nullability: .nonNull
            )))
            let transformResultType = types.make(.classType(ClassType(
                classSymbol: listInterfaceSymbol,
                args: [.out(rType)],
                nullability: .nonNull
            )))
            let transformMemberSymbol = symbols.define(
                kind: .function,
                name: zipWithNextName,
                fqName: zipWithNextTransformFQName,
                declSite: nil,
                visibility: .public,
                flags: [.synthetic, .inlineFunction]
            )
            symbols.setParentSymbol(listInterfaceSymbol, for: transformMemberSymbol)
            symbols.setExternalLinkName("kk_list_zipWithNextTransform", for: transformMemberSymbol)
            symbols.setFunctionSignature(
                FunctionSignature(
                    receiverType: receiverType,
                    parameterTypes: [transformFnType],
                    returnType: transformResultType,
                    typeParameterSymbols: [listTypeParamSymbol, rSymbol],
                    classTypeParameterCount: 1
                ),
                for: transformMemberSymbol
            )
        }
    }
}
