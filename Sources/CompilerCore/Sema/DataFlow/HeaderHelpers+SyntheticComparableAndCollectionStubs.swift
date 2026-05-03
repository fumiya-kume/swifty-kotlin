// swiftlint:disable file_length
import Foundation

/// Centralized FQ-name suffixes used to discriminate the binarySearch
/// overloads from the element-based one. Module-internal so the helper
/// files split from this dispatcher (`+SyntheticListStubs`, `+SyntheticArrayStubs`)
/// can reference them without duplication.
let binarySearchCompareFQSuffix = "binarySearch$compare"
let binarySearchComparatorFQSuffix = "binarySearch$comparator"

extension DataFlowSemaPhase {
    /// Register `kotlin.Comparable<in T>` interface stub with `operator fun compareTo(other: T): Int`.
    func registerSyntheticComparableStub(
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner
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

        let comparableName = interner.intern("Comparable")
        let comparableFQName = kotlinPkg + [comparableName]
        let comparableSymbol: SymbolID = if let existing = symbols.lookup(fqName: comparableFQName) {
            existing
        } else {
            symbols.define(
                kind: .interface,
                name: comparableName,
                fqName: comparableFQName,
                declSite: nil,
                visibility: .public,
                flags: [.synthetic]
            )
        }

        // Store in TypeSystem for use in isSubtype
        types.comparableInterfaceSymbol = comparableSymbol
        types.setNominalTypeParameterVariances([.in], for: comparableSymbol)

        // Define type parameter T for Comparable<in T>.
        let tParamName = interner.intern("T")
        let tParamFQName = comparableFQName + [tParamName]
        let tParamSymbol: SymbolID = if let existing = symbols.lookup(fqName: tParamFQName) {
            existing
        } else {
            symbols.define(
                kind: .typeParameter,
                name: tParamName,
                fqName: tParamFQName,
                declSite: nil,
                visibility: .private,
                flags: []
            )
        }
        let tParamType = types.make(.typeParam(TypeParamType(
            symbol: tParamSymbol, nullability: .nonNull
        )))

        registerComparableCompareToOperator(
            symbols: symbols, types: types, interner: interner,
            comparableFQName: comparableFQName,
            comparableSymbol: comparableSymbol,
            tParamSymbol: tParamSymbol,
            tParamType: tParamType
        )
        registerOpenEndRangeComparableUpperBound(
            comparableSymbol: comparableSymbol,
            symbols: symbols,
            types: types,
            interner: interner
        )
        // Set up primitive types to implement Comparable<Self>
        setupPrimitiveComparableImplementations(symbols: symbols, types: types, interner: interner, comparableSymbol: comparableSymbol)
        patchSyntheticClosedRangeTypeParameterUpperBound(symbols: symbols, types: types, interner: interner)
    }

    func registerSyntheticCollectionStubs(
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner
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

        registerSyntheticPairStub(symbols: symbols, types: types, interner: interner)
        registerSyntheticTripleStub(symbols: symbols, types: types, interner: interner)

        // Ensure the "kotlin.collections" package exists.
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

        let iterableInterfaceSymbol = registerSyntheticIterableStub(
            symbols: symbols, types: types, interner: interner,
            kotlinCollectionsPkg: kotlinCollectionsPkg
        )

        registerIterableAsSequenceMember(
            symbols: symbols, types: types, interner: interner,
            kotlinCollectionsPkg: kotlinCollectionsPkg,
            iterableInterfaceSymbol: iterableInterfaceSymbol
        )
        registerIterableFirstNotNullOfMember(
            symbols: symbols, types: types, interner: interner,
            iterableInterfaceSymbol: iterableInterfaceSymbol
        )
        registerIterableFirstNotNullOfOrNullMember(
            symbols: symbols, types: types, interner: interner,
            iterableInterfaceSymbol: iterableInterfaceSymbol
        )

        // STDLIB-021: Iterable mutable conversion members are registered later once
        // MutableList / MutableSet stubs exist — see calls below after those stubs.

        let collectionInterfaceSymbol = registerSyntheticCollectionStub(
            symbols: symbols, types: types, interner: interner,
            kotlinCollectionsPkg: kotlinCollectionsPkg,
            iterableInterfaceSymbol: iterableInterfaceSymbol
        )

        _ = registerSyntheticAbstractCollectionStub(
            symbols: symbols, types: types, interner: interner,
            kotlinCollectionsPkg: kotlinCollectionsPkg,
            collectionInterfaceSymbol: collectionInterfaceSymbol
        )

        let mutableIterableInterfaceSymbol = registerSyntheticMutableIterableStub(
            symbols: symbols, types: types, interner: interner,
            kotlinCollectionsPkg: kotlinCollectionsPkg,
            iterableInterfaceSymbol: iterableInterfaceSymbol
        )

        let listInterfaceSymbol = registerSyntheticListStub(
            symbols: symbols, types: types, interner: interner,
            kotlinCollectionsPkg: kotlinCollectionsPkg,
            collectionInterfaceSymbol: collectionInterfaceSymbol
        )

        registerIterableWindowedTransformMember(
            symbols: symbols, types: types, interner: interner,
            kotlinCollectionsPkg: kotlinCollectionsPkg,
            iterableInterfaceSymbol: iterableInterfaceSymbol,
            listInterfaceSymbol: listInterfaceSymbol
        )

        // --- STDLIB-533: List?.orEmpty() ---
        let listTypeParamSymbols = types.nominalTypeParameterSymbols(for: listInterfaceSymbol)
        let listTypeParamType = types.make(.typeParam(TypeParamType(
            symbol: listTypeParamSymbols.first!,
            nullability: .nonNull
        )))
        let nullableListType = types.make(.classType(ClassType(
            classSymbol: listInterfaceSymbol,
            args: [.out(listTypeParamType)],
            nullability: .nullable
        )))
        let nonNullListType = types.make(.classType(ClassType(
            classSymbol: listInterfaceSymbol,
            args: [.out(listTypeParamType)],
            nullability: .nonNull
        )))

        registerSyntheticListExtensionFunction(
            named: "orEmpty",
            externalLinkName: "kk_list_orEmpty",
            receiverType: nullableListType,
            parameters: [],
            returnType: nonNullListType,
            typeParameterSymbols: listTypeParamSymbols,
            packageFQName: kotlinCollectionsPkg,
            symbols: symbols,
            types: types,
            interner: interner
        )

        // Now that List is registered, patch Pair.toList() and Triple.toList()
        // return types from the provisional Any? to the correct List<Any?>.
        patchPairTripleToListReturnTypes(
            symbols: symbols, types: types, interner: interner,
            listInterfaceSymbol: listInterfaceSymbol
        )

        registerSyntheticMutableListStub(
            symbols: symbols, types: types, interner: interner,
            kotlinCollectionsPkg: kotlinCollectionsPkg,
            listInterfaceSymbol: listInterfaceSymbol,
            collectionInterfaceSymbol: collectionInterfaceSymbol,
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
            mutableIterableInterfaceSymbol: mutableIterableInterfaceSymbol
        )
        let mapSymbols = registerSyntheticMapStub(
            symbols: symbols, types: types, interner: interner,
            kotlinCollectionsPkg: kotlinCollectionsPkg
        )

        registerListConversionMembers(
            symbols: symbols, types: types, interner: interner,
            kotlinCollectionsPkg: kotlinCollectionsPkg,
            listInterfaceSymbol: listInterfaceSymbol,
            mapInterfaceSymbol: mapSymbols.mapSymbol,
            collectionInterfaceSymbol: collectionInterfaceSymbol
        )

        registerCollectionToListMember(
            symbols: symbols, types: types, interner: interner,
            kotlinCollectionsPkg: kotlinCollectionsPkg,
            collectionInterfaceSymbol: collectionInterfaceSymbol,
            listInterfaceSymbol: listInterfaceSymbol
        )

        // STDLIB-021: Collection.toMutableList() and Iterable mutable conversions
        if let mutableListSym = symbols.lookup(
            fqName: kotlinCollectionsPkg + [interner.intern("MutableList")]
        ),
        let mutableSetSym = symbols.lookup(
            fqName: kotlinCollectionsPkg + [interner.intern("MutableSet")]
        ) {
            registerCollectionToMutableListMember(
                symbols: symbols, types: types, interner: interner,
                kotlinCollectionsPkg: kotlinCollectionsPkg,
                collectionInterfaceSymbol: collectionInterfaceSymbol,
                mutableListSymbol: mutableListSym
            )
            registerIterableToMutableListMember(
                symbols: symbols, types: types, interner: interner,
                kotlinCollectionsPkg: kotlinCollectionsPkg,
                iterableInterfaceSymbol: iterableInterfaceSymbol,
                mutableListSymbol: mutableListSym
            )
            registerIterableToMutableSetMember(
                symbols: symbols, types: types, interner: interner,
                kotlinCollectionsPkg: kotlinCollectionsPkg,
                iterableInterfaceSymbol: iterableInterfaceSymbol,
                mutableSetSymbol: mutableSetSym
            )
            registerIterableToHashSetMember(
                symbols: symbols, types: types, interner: interner,
                kotlinCollectionsPkg: kotlinCollectionsPkg,
                iterableInterfaceSymbol: iterableInterfaceSymbol,
                mutableSetSymbol: mutableSetSym
            )
        }

        registerSyntheticMutableMapStub(
            symbols: symbols, types: types, interner: interner,
            kotlinCollectionsPkg: kotlinCollectionsPkg,
            mapInterfaceSymbol: mapSymbols.mapSymbol,
            keyTypeParamSymbol: mapSymbols.keyTypeParamSymbol,
            valueTypeParamSymbol: mapSymbols.valueTypeParamSymbol
        )
        registerMapToMutableMapMember(
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
            collectionInterfaceSymbol: collectionInterfaceSymbol
        )

        registerSyntheticArrayDequeStub(
            symbols: symbols, types: types, interner: interner,
            kotlinCollectionsPkg: kotlinCollectionsPkg
        )

        // Register type aliases: ArrayList, HashMap, HashSet, LinkedHashMap, LinkedHashSet (STDLIB-560)
        // TODO: Add golden test cases that exercise these aliases in type positions
        //       (e.g. property types, parameter types, return types) to verify
        //       resolveTypeRef expansion works end-to-end.
        registerSyntheticCollectionTypeAliases(
            symbols: symbols, types: types, interner: interner,
            kotlinCollectionsPkg: kotlinCollectionsPkg
        )

        // Register Array<T> and primitive array types (TYPE-103) after collections are registered
        registerSyntheticArrayStubs(
            symbols: symbols, types: types, interner: interner
        )
    }


    func registerLateListIndexedMembers(
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner
    ) {
        let kotlinCollectionsPkg: [InternedString] = [interner.intern("kotlin"), interner.intern("collections")]
        let listFQName = kotlinCollectionsPkg + [interner.intern("List")]
        guard let listInterfaceSymbol = symbols.lookup(fqName: listFQName),
              let listTypeParamSymbol = symbols.lookup(
                  fqName: kotlinCollectionsPkg + [interner.intern("List"), interner.intern("E")]
              )
        else {
            return
        }

        let listTypeParamType = types.make(.typeParam(TypeParamType(
            symbol: listTypeParamSymbol, nullability: .nonNull
        )))
        registerListIndexedMembers(
            symbols: symbols, types: types, interner: interner,
            kotlinCollectionsPkg: kotlinCollectionsPkg,
            listFQName: listFQName,
            listInterfaceSymbol: listInterfaceSymbol,
            listTypeParamSymbol: listTypeParamSymbol,
            listTypeParamType: listTypeParamType
        )
        registerListComponentNMembers(
            symbols: symbols, types: types, interner: interner,
            listFQName: listFQName,
            listInterfaceSymbol: listInterfaceSymbol,
            listTypeParamSymbol: listTypeParamSymbol,
            listTypeParamType: listTypeParamType
        )
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

    func patchArrayBinarySearchComparatorStub(
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner
    ) {
        let arrayFQName = [interner.intern("kotlin"), interner.intern("Array")]
        let binarySearchFQName = arrayFQName + [interner.intern(binarySearchCompareFQSuffix)]
        let comparatorFQName = [interner.intern("kotlin"), interner.intern("Comparator")]
        guard let binarySearchSymbol = symbols.lookup(fqName: binarySearchFQName),
              let comparatorSymbol = symbols.lookup(fqName: comparatorFQName),
              let signature = symbols.functionSignature(for: binarySearchSymbol)
        else {
            return
        }

        guard let elementType = signature.parameterTypes.first else {
            return
        }

        let comparatorType = types.make(.classType(ClassType(
            classSymbol: comparatorSymbol,
            args: [.invariant(elementType)],
            nullability: .nonNull
        )))
        symbols.setFunctionSignature(
            FunctionSignature(
                receiverType: signature.receiverType,
                parameterTypes: [elementType, comparatorType, types.intType, types.intType],
                returnType: signature.returnType,
                isSuspend: signature.isSuspend,
                canThrow: signature.canThrow,
                valueParameterSymbols: signature.valueParameterSymbols,
                valueParameterHasDefaultValues: signature.valueParameterHasDefaultValues,
                valueParameterIsVararg: signature.valueParameterIsVararg,
                typeParameterSymbols: signature.typeParameterSymbols,
                reifiedTypeParameterIndices: signature.reifiedTypeParameterIndices,
                typeParameterUpperBounds: signature.typeParameterUpperBounds,
                typeParameterUpperBoundsList: signature.typeParameterUpperBoundsList,
                classTypeParameterCount: signature.classTypeParameterCount
            ),
            for: binarySearchSymbol
        )
    }

    func patchArraySortedArrayWithComparatorStub(
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner
    ) {
        let arrayFQName = [interner.intern("kotlin"), interner.intern("Array")]
        let sortedArrayWithFQName = arrayFQName + [interner.intern("sortedArrayWith")]
        let comparatorFQName = [interner.intern("kotlin"), interner.intern("Comparator")]
        guard let sortedArrayWithSymbol = symbols.lookup(fqName: sortedArrayWithFQName),
              let comparatorSymbol = symbols.lookup(fqName: comparatorFQName),
              let signature = symbols.functionSignature(for: sortedArrayWithSymbol),
              let receiverType = signature.receiverType
        else {
            return
        }

        let elementType: TypeID
        if case let .classType(arrayType) = types.kind(of: receiverType),
           let firstArg = arrayType.args.first {
            switch firstArg {
            case let .invariant(type), let .out(type), let .in(type):
                elementType = type
            case .star:
                elementType = types.anyType
            }
        } else {
            return
        }

        let comparatorType = types.make(.classType(ClassType(
            classSymbol: comparatorSymbol,
            args: [.invariant(elementType)],
            nullability: .nonNull
        )))
        symbols.setFunctionSignature(
            FunctionSignature(
                receiverType: signature.receiverType,
                parameterTypes: [comparatorType],
                returnType: signature.returnType,
                isSuspend: signature.isSuspend,
                canThrow: signature.canThrow,
                valueParameterSymbols: signature.valueParameterSymbols,
                valueParameterHasDefaultValues: signature.valueParameterHasDefaultValues,
                valueParameterIsVararg: signature.valueParameterIsVararg,
                typeParameterSymbols: signature.typeParameterSymbols,
                reifiedTypeParameterIndices: signature.reifiedTypeParameterIndices,
                typeParameterUpperBounds: signature.typeParameterUpperBounds,
                typeParameterUpperBoundsList: signature.typeParameterUpperBoundsList,
                classTypeParameterCount: signature.classTypeParameterCount
            ),
            for: sortedArrayWithSymbol
        )
    }

}
