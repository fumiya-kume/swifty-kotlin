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

        let mutableIterableInterfaceSymbol = registerSyntheticMutableIterableStub(
            symbols: symbols, types: types, interner: interner,
            kotlinCollectionsPkg: kotlinCollectionsPkg,
            iterableInterfaceSymbol: iterableInterfaceSymbol
        )

        let mutableCollectionInterfaceSymbol = registerSyntheticMutableCollectionStub(
            symbols: symbols, types: types, interner: interner,
            kotlinCollectionsPkg: kotlinCollectionsPkg,
            collectionInterfaceSymbol: collectionInterfaceSymbol
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

    private func registerSyntheticPairStub(
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner
    ) {
        let pairFQName: [InternedString] = [interner.intern("kotlin"), interner.intern("Pair")]
        let pairName = interner.intern("Pair")
        let pairSymbol: SymbolID = if let existing = symbols.lookup(fqName: pairFQName) {
            existing
        } else {
            symbols.define(
                kind: .class,
                name: pairName,
                fqName: pairFQName,
                declSite: nil,
                visibility: .public,
                flags: [.synthetic]
            )
        }

        let firstName = interner.intern("A")
        let secondName = interner.intern("B")
        let firstSymbol = symbols.lookup(fqName: pairFQName + [firstName]) ?? symbols.define(
            kind: .typeParameter,
            name: firstName,
            fqName: pairFQName + [firstName],
            declSite: nil,
            visibility: .private,
            flags: []
        )
        let secondSymbol = symbols.lookup(fqName: pairFQName + [secondName]) ?? symbols.define(
            kind: .typeParameter,
            name: secondName,
            fqName: pairFQName + [secondName],
            declSite: nil,
            visibility: .private,
            flags: []
        )
        types.setNominalTypeParameterSymbols([firstSymbol, secondSymbol], for: pairSymbol)
        types.setNominalTypeParameterVariances([.out, .out], for: pairSymbol)

        let firstType = types.make(.typeParam(TypeParamType(symbol: firstSymbol, nullability: .nonNull)))
        let secondType = types.make(.typeParam(TypeParamType(symbol: secondSymbol, nullability: .nonNull)))
        let pairType = types.make(.classType(ClassType(
            classSymbol: pairSymbol,
            args: [.out(firstType), .out(secondType)],
            nullability: .nonNull
        )))

        func registerFunctionMember(
            name: String,
            returnType: TypeID,
            externalLinkName: String,
            flags: SymbolFlags
        ) {
            let memberName = interner.intern(name)
            let memberFQName = pairFQName + [memberName]
            guard symbols.lookup(fqName: memberFQName) == nil else { return }
            let memberSymbol = symbols.define(
                kind: .function,
                name: memberName,
                fqName: memberFQName,
                declSite: nil,
                visibility: .public,
                flags: flags
            )
            symbols.setParentSymbol(pairSymbol, for: memberSymbol)
            symbols.setExternalLinkName(externalLinkName, for: memberSymbol)
            symbols.setFunctionSignature(
                FunctionSignature(
                    receiverType: pairType,
                    parameterTypes: [],
                    returnType: returnType,
                    typeParameterSymbols: [firstSymbol, secondSymbol],
                    classTypeParameterCount: 2
                ),
                for: memberSymbol
            )
        }

        func registerPropertyMember(name: String, propertyType: TypeID, externalLinkName: String) {
            let memberName = interner.intern(name)
            let memberFQName = pairFQName + [memberName]
            guard symbols.lookup(fqName: memberFQName) == nil else { return }
            let memberSymbol = symbols.define(
                kind: .property,
                name: memberName,
                fqName: memberFQName,
                declSite: nil,
                visibility: .public,
                flags: [.synthetic]
            )
            symbols.setParentSymbol(pairSymbol, for: memberSymbol)
            symbols.setExternalLinkName(externalLinkName, for: memberSymbol)
            symbols.setPropertyType(propertyType, for: memberSymbol)
        }

        // Constructor: Pair(first: A, second: B) -> Pair<A, B>
        let initName = interner.intern("<init>")
        let initFQName = pairFQName + [initName]
        if symbols.lookup(fqName: initFQName) == nil {
            let initSymbol = symbols.define(
                kind: .constructor,
                name: initName,
                fqName: initFQName,
                declSite: nil,
                visibility: .public,
                flags: [.synthetic]
            )
            symbols.setParentSymbol(pairSymbol, for: initSymbol)
            symbols.setExternalLinkName("kk_pair_new", for: initSymbol)

            let firstParamName = interner.intern("first")
            let firstParamSymbol = symbols.define(
                kind: .valueParameter,
                name: firstParamName,
                fqName: initFQName + [firstParamName],
                declSite: nil,
                visibility: .private,
                flags: [.synthetic]
            )
            symbols.setParentSymbol(initSymbol, for: firstParamSymbol)

            let secondParamName = interner.intern("second")
            let secondParamSymbol = symbols.define(
                kind: .valueParameter,
                name: secondParamName,
                fqName: initFQName + [secondParamName],
                declSite: nil,
                visibility: .private,
                flags: [.synthetic]
            )
            symbols.setParentSymbol(initSymbol, for: secondParamSymbol)

            symbols.setFunctionSignature(
                FunctionSignature(
                    receiverType: nil,
                    parameterTypes: [firstType, secondType],
                    returnType: pairType,
                    valueParameterSymbols: [firstParamSymbol, secondParamSymbol],
                    valueParameterHasDefaultValues: [false, false],
                    valueParameterIsVararg: [false, false],
                    typeParameterSymbols: [firstSymbol, secondSymbol],
                    classTypeParameterCount: 2
                ),
                for: initSymbol
            )
        }

        registerFunctionMember(
            name: "component1",
            returnType: firstType,
            externalLinkName: "kk_pair_first",
            flags: [.synthetic, .operatorFunction]
        )
        registerFunctionMember(
            name: "component2",
            returnType: secondType,
            externalLinkName: "kk_pair_second",
            flags: [.synthetic, .operatorFunction]
        )
        registerPropertyMember(name: "first", propertyType: firstType, externalLinkName: "kk_pair_first")
        registerPropertyMember(name: "second", propertyType: secondType, externalLinkName: "kk_pair_second")

        // Pair<A,B>.toString() → kk_pair_to_string
        registerFunctionMember(
            name: "toString",
            returnType: types.stringType,
            externalLinkName: "kk_pair_to_string",
            flags: [.synthetic]
        )

        // Pair<A,B>.toList() returns List<Any?> in Kotlin (elements can be nullable).
        // The List symbol is registered after Pair, so we initially use nullable anyType
        // as a placeholder; patchPairTripleToListReturnTypes() refines this to List<Any?>.
        registerFunctionMember(
            name: "toList",
            returnType: types.makeNullable(types.anyType),
            externalLinkName: "kk_pair_toList",
            flags: [.synthetic]
        )

    }

    private func registerSyntheticTripleStub(
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner
    ) {
        let tripleFQName: [InternedString] = [interner.intern("kotlin"), interner.intern("Triple")]
        let tripleName = interner.intern("Triple")
        let tripleSymbol: SymbolID = if let existing = symbols.lookup(fqName: tripleFQName) {
            existing
        } else {
            symbols.define(
                kind: .class, name: tripleName, fqName: tripleFQName,
                declSite: nil, visibility: .public, flags: [.synthetic]
            )
        }

        let aName = interner.intern("A")
        let bName = interner.intern("B")
        let cName = interner.intern("C")
        let aSymbol = symbols.lookup(fqName: tripleFQName + [aName]) ?? symbols.define(
            kind: .typeParameter, name: aName, fqName: tripleFQName + [aName],
            declSite: nil, visibility: .private, flags: []
        )
        let bSymbol = symbols.lookup(fqName: tripleFQName + [bName]) ?? symbols.define(
            kind: .typeParameter, name: bName, fqName: tripleFQName + [bName],
            declSite: nil, visibility: .private, flags: []
        )
        let cSymbol = symbols.lookup(fqName: tripleFQName + [cName]) ?? symbols.define(
            kind: .typeParameter, name: cName, fqName: tripleFQName + [cName],
            declSite: nil, visibility: .private, flags: []
        )
        types.setNominalTypeParameterSymbols([aSymbol, bSymbol, cSymbol], for: tripleSymbol)
        types.setNominalTypeParameterVariances([.out, .out, .out], for: tripleSymbol)

        let aType = types.make(.typeParam(TypeParamType(symbol: aSymbol, nullability: .nonNull)))
        let bType = types.make(.typeParam(TypeParamType(symbol: bSymbol, nullability: .nonNull)))
        let cType = types.make(.typeParam(TypeParamType(symbol: cSymbol, nullability: .nonNull)))
        let tripleType = types.make(.classType(ClassType(
            classSymbol: tripleSymbol,
            args: [.out(aType), .out(bType), .out(cType)],
            nullability: .nonNull
        )))

        func registerFunctionMember(
            name: String, returnType: TypeID, externalLinkName: String, flags: SymbolFlags
        ) {
            let memberName = interner.intern(name)
            let memberFQName = tripleFQName + [memberName]
            guard symbols.lookup(fqName: memberFQName) == nil else { return }
            let memberSymbol = symbols.define(
                kind: .function, name: memberName, fqName: memberFQName,
                declSite: nil, visibility: .public, flags: flags
            )
            symbols.setParentSymbol(tripleSymbol, for: memberSymbol)
            symbols.setExternalLinkName(externalLinkName, for: memberSymbol)
            symbols.setFunctionSignature(
                FunctionSignature(
                    receiverType: tripleType, parameterTypes: [], returnType: returnType,
                    typeParameterSymbols: [aSymbol, bSymbol, cSymbol], classTypeParameterCount: 3
                ),
                for: memberSymbol
            )
        }

        func registerPropertyMember(name: String, propertyType: TypeID, externalLinkName: String) {
            let memberName = interner.intern(name)
            let memberFQName = tripleFQName + [memberName]
            guard symbols.lookup(fqName: memberFQName) == nil else { return }
            let memberSymbol = symbols.define(
                kind: .property, name: memberName, fqName: memberFQName,
                declSite: nil, visibility: .public, flags: [.synthetic]
            )
            symbols.setParentSymbol(tripleSymbol, for: memberSymbol)
            symbols.setExternalLinkName(externalLinkName, for: memberSymbol)
            symbols.setPropertyType(propertyType, for: memberSymbol)
        }

        // Constructor: Triple(first: A, second: B, third: C) -> Triple<A, B, C>
        let initName = interner.intern("<init>")
        let initFQName = tripleFQName + [initName]
        if symbols.lookup(fqName: initFQName) == nil {
            let initSymbol = symbols.define(
                kind: .constructor,
                name: initName,
                fqName: initFQName,
                declSite: nil,
                visibility: .public,
                flags: [.synthetic]
            )
            symbols.setParentSymbol(tripleSymbol, for: initSymbol)
            symbols.setExternalLinkName("kk_triple_new", for: initSymbol)

            let firstParamName = interner.intern("first")
            let firstParamSymbol = symbols.define(
                kind: .valueParameter,
                name: firstParamName,
                fqName: initFQName + [firstParamName],
                declSite: nil,
                visibility: .private,
                flags: [.synthetic]
            )
            symbols.setParentSymbol(initSymbol, for: firstParamSymbol)

            let secondParamName = interner.intern("second")
            let secondParamSymbol = symbols.define(
                kind: .valueParameter,
                name: secondParamName,
                fqName: initFQName + [secondParamName],
                declSite: nil,
                visibility: .private,
                flags: [.synthetic]
            )
            symbols.setParentSymbol(initSymbol, for: secondParamSymbol)

            let thirdParamName = interner.intern("third")
            let thirdParamSymbol = symbols.define(
                kind: .valueParameter,
                name: thirdParamName,
                fqName: initFQName + [thirdParamName],
                declSite: nil,
                visibility: .private,
                flags: [.synthetic]
            )
            symbols.setParentSymbol(initSymbol, for: thirdParamSymbol)

            symbols.setFunctionSignature(
                FunctionSignature(
                    receiverType: nil,
                    parameterTypes: [aType, bType, cType],
                    returnType: tripleType,
                    valueParameterSymbols: [firstParamSymbol, secondParamSymbol, thirdParamSymbol],
                    valueParameterHasDefaultValues: [false, false, false],
                    valueParameterIsVararg: [false, false, false],
                    typeParameterSymbols: [aSymbol, bSymbol, cSymbol],
                    classTypeParameterCount: 3
                ),
                for: initSymbol
            )
        }

        registerFunctionMember(name: "component1", returnType: aType, externalLinkName: "kk_triple_first", flags: [.synthetic, .operatorFunction])
        registerFunctionMember(name: "component2", returnType: bType, externalLinkName: "kk_triple_second", flags: [.synthetic, .operatorFunction])
        registerFunctionMember(name: "component3", returnType: cType, externalLinkName: "kk_triple_third", flags: [.synthetic, .operatorFunction])
        registerPropertyMember(name: "first", propertyType: aType, externalLinkName: "kk_triple_first")
        registerPropertyMember(name: "second", propertyType: bType, externalLinkName: "kk_triple_second")
        registerPropertyMember(name: "third", propertyType: cType, externalLinkName: "kk_triple_third")

        // Triple<A,B,C>.toString() → kk_triple_to_string
        registerFunctionMember(name: "toString", returnType: types.stringType, externalLinkName: "kk_triple_to_string", flags: [.synthetic])

        // Triple<A,B,C>.toList() returns List<Any?> in Kotlin (elements can be nullable).
        // The List symbol is registered after Triple, so we initially use nullable anyType
        // as a placeholder; patchPairTripleToListReturnTypes() refines this to List<Any?>.
        registerFunctionMember(name: "toList", returnType: types.makeNullable(types.anyType), externalLinkName: "kk_triple_toList", flags: [.synthetic])

    }

    /// Patch the provisional `Any?` return types of `Pair.toList()` and `Triple.toList()`
    /// with the correct `List<Any?>` now that the List symbol is available.
    private func patchPairTripleToListReturnTypes(
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner,
        listInterfaceSymbol: SymbolID
    ) {
        let nullableAnyType = types.makeNullable(types.anyType)
        let listOfNullableAny = types.make(.classType(ClassType(
            classSymbol: listInterfaceSymbol,
            args: [.out(nullableAnyType)],
            nullability: .nonNull
        )))

        // Patch Pair<A,B>.toList() -> List<Any?>
        let pairFQName: [InternedString] = [interner.intern("kotlin"), interner.intern("Pair")]
        let pairToListFQName = pairFQName + [interner.intern("toList")]
        if let pairToListSymbol = symbols.lookup(fqName: pairToListFQName) {
            if let existingSig = symbols.functionSignature(for: pairToListSymbol) {
                symbols.setFunctionSignature(
                    FunctionSignature(
                        receiverType: existingSig.receiverType,
                        parameterTypes: existingSig.parameterTypes,
                        returnType: listOfNullableAny,
                        typeParameterSymbols: existingSig.typeParameterSymbols,
                        classTypeParameterCount: existingSig.classTypeParameterCount
                    ),
                    for: pairToListSymbol
                )
            } else {
                assertionFailure("Pair.toList() symbol found but has no function signature; return type not patched")
            }
        } else {
            assertionFailure("Pair.toList() symbol not found in symbol table; return type not patched")
        }

        // Patch Triple<A,B,C>.toList() -> List<Any?>
        let tripleFQName: [InternedString] = [interner.intern("kotlin"), interner.intern("Triple")]
        let tripleToListFQName = tripleFQName + [interner.intern("toList")]
        if let tripleToListSymbol = symbols.lookup(fqName: tripleToListFQName) {
            if let existingSig = symbols.functionSignature(for: tripleToListSymbol) {
                symbols.setFunctionSignature(
                    FunctionSignature(
                        receiverType: existingSig.receiverType,
                        parameterTypes: existingSig.parameterTypes,
                        returnType: listOfNullableAny,
                        typeParameterSymbols: existingSig.typeParameterSymbols,
                        classTypeParameterCount: existingSig.classTypeParameterCount
                    ),
                    for: tripleToListSymbol
                )
            } else {
                assertionFailure("Triple.toList() symbol found but has no function signature; return type not patched")
            }
        } else {
            assertionFailure("Triple.toList() symbol not found in symbol table; return type not patched")
        }
    }

    private func registerSyntheticCollectionStub(
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner,
        kotlinCollectionsPkg: [InternedString],
        iterableInterfaceSymbol: SymbolID
    ) -> SymbolID {
        let collectionName = interner.intern("Collection")
        let collectionFQName = kotlinCollectionsPkg + [collectionName]
        let collectionInterfaceSymbol: SymbolID = if let existing = symbols.lookup(fqName: collectionFQName) {
            existing
        } else {
            symbols.define(
                kind: .interface,
                name: collectionName,
                fqName: collectionFQName,
                declSite: nil,
                visibility: .public,
                flags: [.synthetic]
            )
        }

        let typeParamName = interner.intern("E")
        let typeParamFQName = collectionFQName + [typeParamName]
        let typeParamSymbol = symbols.define(
            kind: .typeParameter,
            name: typeParamName,
            fqName: typeParamFQName,
            declSite: nil,
            visibility: .private,
            flags: []
        )
        let typeParamType = types.make(.typeParam(TypeParamType(
            symbol: typeParamSymbol, nullability: .nonNull
        )))
        types.setNominalTypeParameterSymbols([typeParamSymbol], for: collectionInterfaceSymbol)
        types.setNominalTypeParameterVariances([.out], for: collectionInterfaceSymbol)
        symbols.setDirectSupertypes([iterableInterfaceSymbol], for: collectionInterfaceSymbol)
        types.setNominalDirectSupertypes([iterableInterfaceSymbol], for: collectionInterfaceSymbol)
        symbols.setSupertypeTypeArgs([.out(typeParamType)], for: collectionInterfaceSymbol, supertype: iterableInterfaceSymbol)
        types.setNominalSupertypeTypeArgs([.out(typeParamType)], for: collectionInterfaceSymbol, supertype: iterableInterfaceSymbol)

        // Register Collection<T> members: size, isEmpty, contains (STDLIB-295)
        let collectionReceiverType = types.make(.classType(ClassType(
            classSymbol: collectionInterfaceSymbol,
            args: [.out(typeParamType)],
            nullability: .nonNull
        )))

        // Helper to define a synthetic Collection function member and register
        // its parent + function signature in one place.
        func defineCollectionFunctionMember(
            name: String,
            parameterTypes: [TypeID],
            returnType: TypeID,
            flags: SymbolFlags
        ) {
            let memberName = interner.intern(name)
            let memberFQName = collectionFQName + [memberName]
            guard symbols.lookup(fqName: memberFQName) == nil else { return }
            let memberSymbol = symbols.define(
                kind: .function,
                name: memberName,
                fqName: memberFQName,
                declSite: nil,
                visibility: .public,
                flags: flags
            )
            symbols.setParentSymbol(collectionInterfaceSymbol, for: memberSymbol)
            symbols.setFunctionSignature(
                FunctionSignature(
                    receiverType: collectionReceiverType,
                    parameterTypes: parameterTypes,
                    returnType: returnType,
                    typeParameterSymbols: [typeParamSymbol],
                    classTypeParameterCount: 1
                ),
                for: memberSymbol
            )
        }

        // size: Int — Kotlin val property, registered as .property kind.
        // NOTE: size is registered inline (not via defineCollectionFunctionMember)
        // because it is a property (.property kind), not a function.
        let sizeName = interner.intern("size")
        let sizeFQName = collectionFQName + [sizeName]
        if symbols.lookup(fqName: sizeFQName) == nil {
            let sizeSymbol = symbols.define(
                kind: .property,
                name: sizeName,
                fqName: sizeFQName,
                declSite: nil,
                visibility: .public,
                flags: [.synthetic]
            )
            symbols.setParentSymbol(collectionInterfaceSymbol, for: sizeSymbol)
            symbols.setPropertyType(types.intType, for: sizeSymbol)
        }

        // isEmpty(): Boolean
        defineCollectionFunctionMember(
            name: "isEmpty",
            parameterTypes: [],
            returnType: types.booleanType,
            flags: [.synthetic]
        )

        // contains(element: E): Boolean — operator for Kotlin `in`.
        // Variance note: Collection declares `out E`, but contains() uses E in
        // parameter (contravariant) position. This matches Kotlin's own declaration
        // where `contains` has `@UnsafeVariance E` — the mismatch is intentional.
        defineCollectionFunctionMember(
            name: "contains",
            parameterTypes: [typeParamType],
            returnType: types.booleanType,
            flags: [.synthetic, .operatorFunction]
        )

        return collectionInterfaceSymbol
    }

    /// Register a minimal `kotlin.collections.MutableCollection<E>` interface surface.
    private func registerSyntheticMutableCollectionStub(
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner,
        kotlinCollectionsPkg: [InternedString],
        collectionInterfaceSymbol: SymbolID
    ) -> SymbolID {
        let mutableCollectionName = interner.intern("MutableCollection")
        let mutableCollectionFQName = kotlinCollectionsPkg + [mutableCollectionName]
        let mutableCollectionSymbol: SymbolID = if let existing = symbols.lookup(fqName: mutableCollectionFQName) {
            existing
        } else {
            symbols.define(
                kind: .interface,
                name: mutableCollectionName,
                fqName: mutableCollectionFQName,
                declSite: nil,
                visibility: .public,
                flags: [.synthetic]
            )
        }

        let typeParamName = interner.intern("E")
        let typeParamFQName = mutableCollectionFQName + [typeParamName]
        let typeParamSymbol: SymbolID = if let existing = symbols.lookup(fqName: typeParamFQName) {
            existing
        } else {
            symbols.define(
                kind: .typeParameter,
                name: typeParamName,
                fqName: typeParamFQName,
                declSite: nil,
                visibility: .private,
                flags: []
            )
        }
        let typeParamType = types.make(.typeParam(TypeParamType(
            symbol: typeParamSymbol,
            nullability: .nonNull
        )))
        types.setNominalTypeParameterSymbols([typeParamSymbol], for: mutableCollectionSymbol)
        types.setNominalTypeParameterVariances([.invariant], for: mutableCollectionSymbol)
        symbols.setDirectSupertypes([collectionInterfaceSymbol], for: mutableCollectionSymbol)
        types.setNominalDirectSupertypes([collectionInterfaceSymbol], for: mutableCollectionSymbol)
        symbols.setSupertypeTypeArgs([.out(typeParamType)], for: mutableCollectionSymbol, supertype: collectionInterfaceSymbol)
        types.setNominalSupertypeTypeArgs([.out(typeParamType)], for: mutableCollectionSymbol, supertype: collectionInterfaceSymbol)

        let mutableCollectionType = types.make(.classType(ClassType(
            classSymbol: mutableCollectionSymbol,
            args: [.invariant(typeParamType)],
            nullability: .nonNull
        )))
        let collectionType = types.make(.classType(ClassType(
            classSymbol: collectionInterfaceSymbol,
            args: [.out(typeParamType)],
            nullability: .nonNull
        )))

        func registerMutableCollectionFunction(
            name: String,
            parameterTypes: [TypeID],
            returnType: TypeID,
            valueParameterNames: [String] = []
        ) {
            let memberName = interner.intern(name)
            let memberFQName = mutableCollectionFQName + [memberName]
            guard symbols.lookup(fqName: memberFQName) == nil else { return }
            let memberSymbol = symbols.define(
                kind: .function,
                name: memberName,
                fqName: memberFQName,
                declSite: nil,
                visibility: .public,
                flags: [.synthetic]
            )
            symbols.setParentSymbol(mutableCollectionSymbol, for: memberSymbol)

            var valueParameterSymbols: [SymbolID] = []
            for parameterName in valueParameterNames {
                let interned = interner.intern(parameterName)
                let parameterSymbol = symbols.define(
                    kind: .valueParameter,
                    name: interned,
                    fqName: memberFQName + [interned],
                    declSite: nil,
                    visibility: .private,
                    flags: [.synthetic]
                )
                symbols.setParentSymbol(memberSymbol, for: parameterSymbol)
                valueParameterSymbols.append(parameterSymbol)
            }

            symbols.setFunctionSignature(
                FunctionSignature(
                    receiverType: mutableCollectionType,
                    parameterTypes: parameterTypes,
                    returnType: returnType,
                    valueParameterSymbols: valueParameterSymbols,
                    valueParameterHasDefaultValues: Array(repeating: false, count: valueParameterSymbols.count),
                    valueParameterIsVararg: Array(repeating: false, count: valueParameterSymbols.count),
                    typeParameterSymbols: [typeParamSymbol],
                    classTypeParameterCount: 1
                ),
                for: memberSymbol
            )
        }

        registerMutableCollectionFunction(
            name: "add",
            parameterTypes: [typeParamType],
            returnType: types.booleanType,
            valueParameterNames: ["element"]
        )
        registerMutableCollectionFunction(
            name: "addAll",
            parameterTypes: [collectionType],
            returnType: types.booleanType,
            valueParameterNames: ["elements"]
        )
        registerMutableCollectionFunction(
            name: "clear",
            parameterTypes: [],
            returnType: types.unitType
        )
        registerMutableCollectionFunction(
            name: "remove",
            parameterTypes: [typeParamType],
            returnType: types.booleanType,
            valueParameterNames: ["element"]
        )
        registerMutableCollectionFunction(
            name: "removeAll",
            parameterTypes: [collectionType],
            returnType: types.booleanType,
            valueParameterNames: ["elements"]
        )
        registerMutableCollectionFunction(
            name: "retainAll",
            parameterTypes: [collectionType],
            returnType: types.booleanType,
            valueParameterNames: ["elements"]
        )

        return mutableCollectionSymbol
    }

    /// Register `kotlin.collections.AbstractMutableCollection<E>` surface (STDLIB-COL-TYPE-003).
    private func registerSyntheticAbstractMutableCollectionStub(
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner,
        kotlinCollectionsPkg: [InternedString],
        collectionInterfaceSymbol: SymbolID,
        mutableCollectionInterfaceSymbol: SymbolID
    ) {
        let abstractMutableCollectionName = interner.intern("AbstractMutableCollection")
        let abstractMutableCollectionFQName = kotlinCollectionsPkg + [abstractMutableCollectionName]
        let abstractMutableCollectionSymbol: SymbolID = if let existing = symbols.lookup(fqName: abstractMutableCollectionFQName) {
            existing
        } else {
            symbols.define(
                kind: .class,
                name: abstractMutableCollectionName,
                fqName: abstractMutableCollectionFQName,
                declSite: nil,
                visibility: .public,
                flags: [.synthetic, .abstractType]
            )
        }

        let typeParamName = interner.intern("E")
        let typeParamFQName = abstractMutableCollectionFQName + [typeParamName]
        let typeParamSymbol: SymbolID = if let existing = symbols.lookup(fqName: typeParamFQName) {
            existing
        } else {
            symbols.define(
                kind: .typeParameter,
                name: typeParamName,
                fqName: typeParamFQName,
                declSite: nil,
                visibility: .private,
                flags: []
            )
        }
        let typeParamType = types.make(.typeParam(TypeParamType(
            symbol: typeParamSymbol,
            nullability: .nonNull
        )))
        types.setNominalTypeParameterSymbols([typeParamSymbol], for: abstractMutableCollectionSymbol)
        types.setNominalTypeParameterVariances([.invariant], for: abstractMutableCollectionSymbol)

        let abstractMutableCollectionType = types.make(.classType(ClassType(
            classSymbol: abstractMutableCollectionSymbol,
            args: [.invariant(typeParamType)],
            nullability: .nonNull
        )))
        symbols.setPropertyType(abstractMutableCollectionType, for: abstractMutableCollectionSymbol)

        let abstractCollectionFQName = kotlinCollectionsPkg + [interner.intern("AbstractCollection")]
        let readonlyCollectionSupertype = symbols.lookup(fqName: abstractCollectionFQName) ?? collectionInterfaceSymbol
        symbols.setDirectSupertypes([readonlyCollectionSupertype, mutableCollectionInterfaceSymbol], for: abstractMutableCollectionSymbol)
        types.setNominalDirectSupertypes([readonlyCollectionSupertype, mutableCollectionInterfaceSymbol], for: abstractMutableCollectionSymbol)
        symbols.setSupertypeTypeArgs([.out(typeParamType)], for: abstractMutableCollectionSymbol, supertype: readonlyCollectionSupertype)
        types.setNominalSupertypeTypeArgs([.out(typeParamType)], for: abstractMutableCollectionSymbol, supertype: readonlyCollectionSupertype)
        symbols.setSupertypeTypeArgs([.invariant(typeParamType)], for: abstractMutableCollectionSymbol, supertype: mutableCollectionInterfaceSymbol)
        types.setNominalSupertypeTypeArgs([.invariant(typeParamType)], for: abstractMutableCollectionSymbol, supertype: mutableCollectionInterfaceSymbol)

        let initName = interner.intern("<init>")
        let initFQName = abstractMutableCollectionFQName + [initName]
        if symbols.lookup(fqName: initFQName) == nil {
            let initSymbol = symbols.define(
                kind: .constructor,
                name: initName,
                fqName: initFQName,
                declSite: nil,
                visibility: .protected,
                flags: [.synthetic]
            )
            symbols.setParentSymbol(abstractMutableCollectionSymbol, for: initSymbol)
            symbols.setFunctionSignature(
                FunctionSignature(
                    receiverType: nil,
                    parameterTypes: [],
                    returnType: abstractMutableCollectionType,
                    valueParameterSymbols: [],
                    valueParameterHasDefaultValues: [],
                    valueParameterIsVararg: [],
                    typeParameterSymbols: [typeParamSymbol],
                    classTypeParameterCount: 1
                ),
                for: initSymbol
            )
        }
    }

    /// Register `Collection<E>.toList(): List<E>` so that `keys.toList()` / `values.toList()` resolve.
    /// Also registers `Collection<E>.toCollection(destination)` for destination appends.
    /// Must be called after both Collection and List stubs are registered.
    private func registerCollectionToListMember(
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner,
        kotlinCollectionsPkg: [InternedString],
        collectionInterfaceSymbol: SymbolID,
        listInterfaceSymbol: SymbolID
    ) {
        let collectionFQName = kotlinCollectionsPkg + [interner.intern("Collection")]
        guard let typeParamSymbol = symbols.lookup(
            fqName: collectionFQName + [interner.intern("E")]
        ) else { return }
        let typeParamType = types.make(.typeParam(TypeParamType(
            symbol: typeParamSymbol, nullability: .nonNull
        )))
        let collectionReceiverType = types.make(.classType(ClassType(
            classSymbol: collectionInterfaceSymbol,
            args: [.out(typeParamType)],
            nullability: .nonNull
        )))
        let listReturnType = types.make(.classType(ClassType(
            classSymbol: listInterfaceSymbol,
            args: [.out(typeParamType)],
            nullability: .nonNull
        )))

        let memberName = interner.intern("toList")
        let memberFQName = collectionFQName + [memberName]
        guard symbols.lookup(fqName: memberFQName) == nil else { return }
        let memberSymbol = symbols.define(
            kind: .function,
            name: memberName,
            fqName: memberFQName,
            declSite: nil,
            visibility: .public,
            flags: [.synthetic]
        )
        symbols.setParentSymbol(collectionInterfaceSymbol, for: memberSymbol)
        symbols.setExternalLinkName("kk_collection_toList", for: memberSymbol)
        symbols.setFunctionSignature(
            FunctionSignature(
                receiverType: collectionReceiverType,
                parameterTypes: [],
                returnType: listReturnType,
                typeParameterSymbols: [typeParamSymbol],
                classTypeParameterCount: 1
            ),
            for: memberSymbol
        )

        let toCollectionName = interner.intern("toCollection")
        let toCollectionFQName = collectionFQName + [toCollectionName]
        if symbols.lookup(fqName: toCollectionFQName) == nil {
            let toCollectionSym = symbols.define(
                kind: .function,
                name: toCollectionName,
                fqName: toCollectionFQName,
                declSite: nil,
                visibility: .public,
                flags: [.synthetic]
            )
            symbols.setParentSymbol(collectionInterfaceSymbol, for: toCollectionSym)
            symbols.setExternalLinkName("kk_collection_toCollection", for: toCollectionSym)
            symbols.setFunctionSignature(
                FunctionSignature(
                    receiverType: collectionReceiverType,
                    parameterTypes: [collectionReceiverType],
                    returnType: collectionReceiverType,
                    typeParameterSymbols: [typeParamSymbol],
                    classTypeParameterCount: 1
                ),
                for: toCollectionSym
            )
        }
    }

    /// Register `Collection<E>.toMutableList(): MutableList<E>` (STDLIB-021).
    private func registerCollectionToMutableListMember(
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner,
        kotlinCollectionsPkg: [InternedString],
        collectionInterfaceSymbol: SymbolID,
        mutableListSymbol: SymbolID
    ) {
        let collectionFQName = kotlinCollectionsPkg + [interner.intern("Collection")]
        guard let typeParamSymbol = symbols.lookup(
            fqName: collectionFQName + [interner.intern("E")]
        ) else { return }
        let typeParamType = types.make(.typeParam(TypeParamType(
            symbol: typeParamSymbol, nullability: .nonNull
        )))
        let collectionReceiverType = types.make(.classType(ClassType(
            classSymbol: collectionInterfaceSymbol,
            args: [.out(typeParamType)],
            nullability: .nonNull
        )))
        let mutableListReturnType = types.make(.classType(ClassType(
            classSymbol: mutableListSymbol,
            args: [.invariant(typeParamType)],
            nullability: .nonNull
        )))

        let memberName = interner.intern("toMutableList")
        let memberFQName = collectionFQName + [memberName]
        guard symbols.lookup(fqName: memberFQName) == nil else { return }
        let memberSymbol = symbols.define(
            kind: .function,
            name: memberName,
            fqName: memberFQName,
            declSite: nil,
            visibility: .public,
            flags: [.synthetic]
        )
        symbols.setParentSymbol(collectionInterfaceSymbol, for: memberSymbol)
        symbols.setExternalLinkName("kk_collection_toMutableList", for: memberSymbol)
        symbols.setFunctionSignature(
            FunctionSignature(
                receiverType: collectionReceiverType,
                parameterTypes: [],
                returnType: mutableListReturnType,
                typeParameterSymbols: [typeParamSymbol],
                classTypeParameterCount: 1
            ),
            for: memberSymbol
        )
    }

    /// Register `Iterable<E>.toMutableList(): MutableList<E>` (STDLIB-021).
    private func registerIterableToMutableListMember(
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner,
        kotlinCollectionsPkg: [InternedString],
        iterableInterfaceSymbol: SymbolID,
        mutableListSymbol: SymbolID
    ) {
        guard let iterableFQName = symbols.symbol(iterableInterfaceSymbol)?.fqName else { return }
        let memberName = interner.intern("toMutableList")
        let memberFQName = iterableFQName + [memberName]
        guard symbols.lookup(fqName: memberFQName) == nil else { return }

        let typeParamName = interner.intern("E")
        let typeParamFQName = iterableFQName + [typeParamName]
        guard let typeParamSymbol = symbols.lookup(fqName: typeParamFQName) else { return }
        let typeParamType = types.make(.typeParam(TypeParamType(
            symbol: typeParamSymbol, nullability: .nonNull
        )))

        let receiverType = types.make(.classType(ClassType(
            classSymbol: iterableInterfaceSymbol,
            args: [.out(typeParamType)],
            nullability: .nonNull
        )))
        let returnType = types.make(.classType(ClassType(
            classSymbol: mutableListSymbol,
            args: [.invariant(typeParamType)],
            nullability: .nonNull
        )))
        let memberSymbol = symbols.define(
            kind: .function,
            name: memberName,
            fqName: memberFQName,
            declSite: nil,
            visibility: .public,
            flags: [.synthetic]
        )
        symbols.setParentSymbol(iterableInterfaceSymbol, for: memberSymbol)
        symbols.setExternalLinkName("kk_iterable_toMutableList", for: memberSymbol)
        symbols.setFunctionSignature(
            FunctionSignature(
                receiverType: receiverType,
                parameterTypes: [],
                returnType: returnType,
                typeParameterSymbols: [typeParamSymbol],
                classTypeParameterCount: 1
            ),
            for: memberSymbol
        )
    }

    /// Register `Iterable<E>.toMutableSet(): MutableSet<E>` (STDLIB-021).
    private func registerIterableToMutableSetMember(
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner,
        kotlinCollectionsPkg: [InternedString],
        iterableInterfaceSymbol: SymbolID,
        mutableSetSymbol: SymbolID
    ) {
        guard let iterableFQName = symbols.symbol(iterableInterfaceSymbol)?.fqName else { return }
        let memberName = interner.intern("toMutableSet")
        let memberFQName = iterableFQName + [memberName]
        guard symbols.lookup(fqName: memberFQName) == nil else { return }

        let typeParamName = interner.intern("E")
        let typeParamFQName = iterableFQName + [typeParamName]
        guard let typeParamSymbol = symbols.lookup(fqName: typeParamFQName) else { return }
        let typeParamType = types.make(.typeParam(TypeParamType(
            symbol: typeParamSymbol, nullability: .nonNull
        )))

        let receiverType = types.make(.classType(ClassType(
            classSymbol: iterableInterfaceSymbol,
            args: [.out(typeParamType)],
            nullability: .nonNull
        )))
        let returnType = types.make(.classType(ClassType(
            classSymbol: mutableSetSymbol,
            args: [.invariant(typeParamType)],
            nullability: .nonNull
        )))
        let memberSymbol = symbols.define(
            kind: .function,
            name: memberName,
            fqName: memberFQName,
            declSite: nil,
            visibility: .public,
            flags: [.synthetic]
        )
        symbols.setParentSymbol(iterableInterfaceSymbol, for: memberSymbol)
        symbols.setExternalLinkName("kk_iterable_toMutableSet", for: memberSymbol)
        symbols.setFunctionSignature(
            FunctionSignature(
                receiverType: receiverType,
                parameterTypes: [],
                returnType: returnType,
                typeParameterSymbols: [typeParamSymbol],
                classTypeParameterCount: 1
            ),
            for: memberSymbol
        )
    }

    /// Register `Iterable<E>.toHashSet(): HashSet<E>` (STDLIB-021).
    /// At runtime HashSet is backed by the same RuntimeSetBox as MutableSet.
    private func registerIterableToHashSetMember(
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner,
        kotlinCollectionsPkg: [InternedString],
        iterableInterfaceSymbol: SymbolID,
        mutableSetSymbol: SymbolID
    ) {
        guard let iterableFQName = symbols.symbol(iterableInterfaceSymbol)?.fqName else { return }
        let memberName = interner.intern("toHashSet")
        let memberFQName = iterableFQName + [memberName]
        guard symbols.lookup(fqName: memberFQName) == nil else { return }

        let typeParamName = interner.intern("E")
        let typeParamFQName = iterableFQName + [typeParamName]
        guard let typeParamSymbol = symbols.lookup(fqName: typeParamFQName) else { return }
        let typeParamType = types.make(.typeParam(TypeParamType(
            symbol: typeParamSymbol, nullability: .nonNull
        )))

        let receiverType = types.make(.classType(ClassType(
            classSymbol: iterableInterfaceSymbol,
            args: [.out(typeParamType)],
            nullability: .nonNull
        )))
        // Return MutableSet<E> (HashSet is a type alias for MutableSet at the runtime level)
        let returnType = types.make(.classType(ClassType(
            classSymbol: mutableSetSymbol,
            args: [.invariant(typeParamType)],
            nullability: .nonNull
        )))
        let memberSymbol = symbols.define(
            kind: .function,
            name: memberName,
            fqName: memberFQName,
            declSite: nil,
            visibility: .public,
            flags: [.synthetic]
        )
        symbols.setParentSymbol(iterableInterfaceSymbol, for: memberSymbol)
        symbols.setExternalLinkName("kk_iterable_toHashSet", for: memberSymbol)
        symbols.setFunctionSignature(
            FunctionSignature(
                receiverType: receiverType,
                parameterTypes: [],
                returnType: returnType,
                typeParameterSymbols: [typeParamSymbol],
                classTypeParameterCount: 1
            ),
            for: memberSymbol
        )
    }

    private func registerSyntheticIterableStub(
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner,
        kotlinCollectionsPkg: [InternedString]
    ) -> SymbolID {
        let iterableName = interner.intern("Iterable")
        let iterableFQName = kotlinCollectionsPkg + [iterableName]
        let iterableInterfaceSymbol: SymbolID = if let existing = symbols.lookup(fqName: iterableFQName) {
            existing
        } else {
            symbols.define(
                kind: .interface,
                name: iterableName,
                fqName: iterableFQName,
                declSite: nil,
                visibility: .public,
                flags: [.synthetic]
            )
        }

        let typeParamName = interner.intern("E")
        let typeParamFQName = iterableFQName + [typeParamName]
        let typeParamSymbol = symbols.define(
            kind: .typeParameter,
            name: typeParamName,
            fqName: typeParamFQName,
            declSite: nil,
            visibility: .private,
            flags: []
        )
        types.setNominalTypeParameterSymbols([typeParamSymbol], for: iterableInterfaceSymbol)
        types.setNominalTypeParameterVariances([.out], for: iterableInterfaceSymbol)

        // Register Iterator<T> interface (STDLIB-221)
        let iteratorName = interner.intern("Iterator")
        let iteratorFQName = kotlinCollectionsPkg + [iteratorName]
        let iteratorSymbol: SymbolID = if let existing = symbols.lookup(fqName: iteratorFQName) {
            existing
        } else {
            symbols.define(
                kind: .interface,
                name: iteratorName,
                fqName: iteratorFQName,
                declSite: nil,
                visibility: .public,
                flags: [.synthetic]
            )
        }
        let itTypeParamName = interner.intern("T")
        let itTypeParamFQName = iteratorFQName + [itTypeParamName]
        let itTypeParamSymbol = symbols.define(
            kind: .typeParameter,
            name: itTypeParamName,
            fqName: itTypeParamFQName,
            declSite: nil,
            visibility: .private,
            flags: []
        )
        types.setNominalTypeParameterSymbols([itTypeParamSymbol], for: iteratorSymbol)
        types.setNominalTypeParameterVariances([.out], for: iteratorSymbol)
        let iteratorTypeParamType = types.make(.typeParam(TypeParamType(
            symbol: itTypeParamSymbol,
            nullability: .nonNull
        )))
        let iteratorReceiverType = types.make(.classType(ClassType(
            classSymbol: iteratorSymbol,
            args: [.out(iteratorTypeParamType)],
            nullability: .nonNull
        )))

        // Iterable.iterator(): Iterator<E>
        let iterFnName = interner.intern("iterator")
        let iterFnFQName = iterableFQName + [iterFnName]
        if symbols.lookup(fqName: iterFnFQName) == nil {
            let typeParamType = types.make(.typeParam(TypeParamType(
                symbol: typeParamSymbol,
                nullability: .nonNull
            )))
            let iterableReceiverType = types.make(.classType(ClassType(
                classSymbol: iterableInterfaceSymbol,
                args: [.out(typeParamType)],
                nullability: .nonNull
            )))
            let iteratorReturnType = types.make(.classType(ClassType(
                classSymbol: iteratorSymbol,
                args: [.out(typeParamType)],
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
            symbols.setParentSymbol(iterableInterfaceSymbol, for: iterFnSymbol)
            symbols.setExternalLinkName("kk_range_iterator", for: iterFnSymbol)
            symbols.setPropertyType(types.make(.functionType(FunctionType(
                params: [],
                returnType: iteratorReturnType,
                isSuspend: false,
                nullability: .nonNull
            ))), for: iterFnSymbol)
            symbols.setFunctionSignature(
                FunctionSignature(
                    receiverType: iterableReceiverType,
                    parameterTypes: [],
                    returnType: iteratorReturnType,
                    typeParameterSymbols: [typeParamSymbol],
                    classTypeParameterCount: 1
                ),
                for: iterFnSymbol
            )
        }

        // Iterator.hasNext(): Boolean
        let hasNextName = interner.intern("hasNext")
        let hasNextFQName = iteratorFQName + [hasNextName]
        if symbols.lookup(fqName: hasNextFQName) == nil {
            let sym = symbols.define(
                kind: .function, name: hasNextName, fqName: hasNextFQName,
                declSite: nil, visibility: .public, flags: [.synthetic]
            )
            symbols.setParentSymbol(iteratorSymbol, for: sym)
            symbols.setExternalLinkName("kk_iterator_hasNext", for: sym)
            symbols.setPropertyType(types.make(.functionType(FunctionType(
                params: [], returnType: types.booleanType, isSuspend: false, nullability: .nonNull
            ))), for: sym)
            symbols.setFunctionSignature(
                FunctionSignature(
                    receiverType: iteratorReceiverType,
                    parameterTypes: [],
                    returnType: types.booleanType,
                    typeParameterSymbols: [itTypeParamSymbol],
                    classTypeParameterCount: 1
                ),
                for: sym
            )
        }

        // Iterator.next(): T
        let nextName = interner.intern("next")
        let nextFQName = iteratorFQName + [nextName]
        if symbols.lookup(fqName: nextFQName) == nil {
            let sym = symbols.define(
                kind: .function, name: nextName, fqName: nextFQName,
                declSite: nil, visibility: .public, flags: [.synthetic]
            )
            symbols.setParentSymbol(iteratorSymbol, for: sym)
            symbols.setExternalLinkName("kk_iterator_next", for: sym)
            symbols.setPropertyType(types.make(.functionType(FunctionType(
                params: [], returnType: iteratorTypeParamType, isSuspend: false, nullability: .nonNull
            ))), for: sym)
            symbols.setFunctionSignature(
                FunctionSignature(
                    receiverType: iteratorReceiverType,
                    parameterTypes: [],
                    returnType: iteratorTypeParamType,
                    typeParameterSymbols: [itTypeParamSymbol],
                    classTypeParameterCount: 1
                ),
                for: sym
            )
        }

        // MutableIterator<T> : Iterator<T> (STDLIB-221)
        let mutableIteratorName = interner.intern("MutableIterator")
        let mutableIteratorFQName = kotlinCollectionsPkg + [mutableIteratorName]
        let mutableIteratorSymbol: SymbolID = if let existing = symbols.lookup(fqName: mutableIteratorFQName) {
            existing
        } else {
            symbols.define(
                kind: .interface, name: mutableIteratorName, fqName: mutableIteratorFQName,
                declSite: nil, visibility: .public, flags: [.synthetic]
            )
        }
        let mutableIteratorTypeParamName = interner.intern("T")
        let mutableIteratorTypeParamFQName = mutableIteratorFQName + [mutableIteratorTypeParamName]
        let mutableIteratorTypeParamSymbol: SymbolID = if let existing = symbols.lookup(fqName: mutableIteratorTypeParamFQName) {
            existing
        } else {
            symbols.define(
                kind: .typeParameter,
                name: mutableIteratorTypeParamName,
                fqName: mutableIteratorTypeParamFQName,
                declSite: nil,
                visibility: .private,
                flags: []
            )
        }
        let mutableIteratorTypeParamType = types.make(.typeParam(TypeParamType(
            symbol: mutableIteratorTypeParamSymbol,
            nullability: .nonNull
        )))
        let mutableIteratorReceiverType = types.make(.classType(ClassType(
            classSymbol: mutableIteratorSymbol,
            args: [.out(mutableIteratorTypeParamType)],
            nullability: .nonNull
        )))
        types.setNominalTypeParameterSymbols([mutableIteratorTypeParamSymbol], for: mutableIteratorSymbol)
        types.setNominalTypeParameterVariances([.out], for: mutableIteratorSymbol)
        symbols.setDirectSupertypes([iteratorSymbol], for: mutableIteratorSymbol)
        types.setNominalDirectSupertypes([iteratorSymbol], for: mutableIteratorSymbol)
        symbols.setSupertypeTypeArgs([.out(mutableIteratorTypeParamType)], for: mutableIteratorSymbol, supertype: iteratorSymbol)
        types.setNominalSupertypeTypeArgs([.out(mutableIteratorTypeParamType)], for: mutableIteratorSymbol, supertype: iteratorSymbol)

        // MutableIterator.remove(): Unit
        let removeName = interner.intern("remove")
        let removeFQName = mutableIteratorFQName + [removeName]
        if symbols.lookup(fqName: removeFQName) == nil {
            let removeSymbol = symbols.define(
                kind: .function, name: removeName, fqName: removeFQName,
                declSite: nil, visibility: .public, flags: [.synthetic]
            )
            symbols.setParentSymbol(mutableIteratorSymbol, for: removeSymbol)
            symbols.setPropertyType(types.make(.functionType(FunctionType(
                params: [], returnType: types.unitType, isSuspend: false, nullability: .nonNull
            ))), for: removeSymbol)
            symbols.setFunctionSignature(
                FunctionSignature(
                    receiverType: mutableIteratorReceiverType,
                    parameterTypes: [],
                    returnType: types.unitType,
                    typeParameterSymbols: [mutableIteratorTypeParamSymbol],
                    classTypeParameterCount: 1
                ),
                for: removeSymbol
            )
        }

        return iterableInterfaceSymbol
    }

    /// Register `kotlin.collections.MutableIterable<T>` surface (STDLIB-COL-TYPE-005).
    private func registerSyntheticMutableIterableStub(
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner,
        kotlinCollectionsPkg: [InternedString],
        iterableInterfaceSymbol: SymbolID
    ) -> SymbolID {
        let mutableIterableName = interner.intern("MutableIterable")
        let mutableIterableFQName = kotlinCollectionsPkg + [mutableIterableName]
        let mutableIterableSymbol: SymbolID = if let existing = symbols.lookup(fqName: mutableIterableFQName) {
            existing
        } else {
            symbols.define(
                kind: .interface,
                name: mutableIterableName,
                fqName: mutableIterableFQName,
                declSite: nil,
                visibility: .public,
                flags: [.synthetic]
            )
        }

        let typeParamName = interner.intern("T")
        let typeParamFQName = mutableIterableFQName + [typeParamName]
        let typeParamSymbol: SymbolID = if let existing = symbols.lookup(fqName: typeParamFQName) {
            existing
        } else {
            symbols.define(
                kind: .typeParameter,
                name: typeParamName,
                fqName: typeParamFQName,
                declSite: nil,
                visibility: .private,
                flags: []
            )
        }
        let typeParamType = types.make(.typeParam(TypeParamType(
            symbol: typeParamSymbol,
            nullability: .nonNull
        )))
        types.setNominalTypeParameterSymbols([typeParamSymbol], for: mutableIterableSymbol)
        types.setNominalTypeParameterVariances([.out], for: mutableIterableSymbol)
        symbols.setDirectSupertypes([iterableInterfaceSymbol], for: mutableIterableSymbol)
        types.setNominalDirectSupertypes([iterableInterfaceSymbol], for: mutableIterableSymbol)
        symbols.setSupertypeTypeArgs([.invariant(typeParamType)], for: mutableIterableSymbol, supertype: iterableInterfaceSymbol)
        types.setNominalSupertypeTypeArgs([.invariant(typeParamType)], for: mutableIterableSymbol, supertype: iterableInterfaceSymbol)

        let mutableIterableType = types.make(.classType(ClassType(
            classSymbol: mutableIterableSymbol,
            args: [.out(typeParamType)],
            nullability: .nonNull
        )))

        let mutableIteratorFQName = kotlinCollectionsPkg + [interner.intern("MutableIterator")]
        guard let mutableIteratorSymbol = symbols.lookup(fqName: mutableIteratorFQName) else {
            assertionFailure("MutableIterator must be registered before MutableIterable")
            return mutableIterableSymbol
        }
        let mutableIteratorType = types.make(.classType(ClassType(
            classSymbol: mutableIteratorSymbol,
            args: [.out(typeParamType)],
            nullability: .nonNull
        )))

        let iteratorName = interner.intern("iterator")
        let iteratorFQName = mutableIterableFQName + [iteratorName]
        if symbols.lookup(fqName: iteratorFQName) == nil {
            let iteratorSymbol = symbols.define(
                kind: .function,
                name: iteratorName,
                fqName: iteratorFQName,
                declSite: nil,
                visibility: .public,
                flags: [.synthetic, .operatorFunction]
            )
            symbols.setParentSymbol(mutableIterableSymbol, for: iteratorSymbol)
            symbols.setFunctionSignature(
                FunctionSignature(
                    receiverType: mutableIterableType,
                    parameterTypes: [],
                    returnType: mutableIteratorType,
                    typeParameterSymbols: [typeParamSymbol],
                    classTypeParameterCount: 1
                ),
                for: iteratorSymbol
            )
        }

        return mutableIterableSymbol
    }

    /// Ensure the synthetic `kotlin.sequences.Sequence<T>` interface stub exists,
    /// including its `operator fun iterator(): Iterator<T>` member.
    ///
    /// This helper is idempotent: it creates the package, interface, type parameter,
    /// and `iterator()` member only if they are not already present.  Callers that
    /// need a `Sequence` return type (e.g., `asSequence()` on various collection
    /// types) should call this first and use the returned `SymbolID`.
    private func ensureSyntheticSequenceStub(
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner,
        kotlinCollectionsPkg: [InternedString]
    ) -> SymbolID {
        // Step 1: Ensure the kotlin.sequences package exists.
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

        // Step 2: Ensure the Sequence interface exists.
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

        // Step 3: Ensure the type parameter T on Sequence exists.
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

        // Step 4: Ensure `operator fun iterator(): Iterator<T>` exists on Sequence,
        // independently of whether the type parameter was newly created above.
        // This prevents the case where Sequence<T> already exists (e.g., created
        // elsewhere) but iterator() is missing.
        let iterFnName = interner.intern("iterator")
        let iterFnFQName = sequenceFQName + [iterFnName]
        if symbols.lookup(fqName: iterFnFQName) == nil {
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

        // STDLIB-SEQ-008: Sequence<T>.chunked(size, transform): Sequence<R>
        let chunkedName = interner.intern("chunked")
        let chunkedFQName = sequenceFQName + [chunkedName]
        if let seqTypeParamSymbol = symbols.lookup(fqName: seqTypeParamFQName),
           let listSymbol = symbols.lookup(fqName: kotlinCollectionsPkg + [interner.intern("List")])
        {
            let seqTypeParamType = types.make(.typeParam(TypeParamType(
                symbol: seqTypeParamSymbol,
                nullability: .nonNull
            )))
            let chunkParameterType = types.make(.classType(ClassType(
                classSymbol: listSymbol,
                args: [.invariant(seqTypeParamType)],
                nullability: .nonNull
            )))
            let transformType = types.make(.functionType(FunctionType(
                params: [chunkParameterType],
                returnType: types.anyType,
                isSuspend: false,
                nullability: .nonNull
            )))
            let sequenceReturnType = types.make(.classType(ClassType(
                classSymbol: sequenceSymbol,
                args: [.out(types.anyType)],
                nullability: .nonNull
            )))
            let alreadyRegistered = symbols.lookupAll(fqName: chunkedFQName).contains { symID in
                guard let sig = symbols.functionSignature(for: symID) else { return false }
                return sig.parameterTypes.count == 2
                    && symbols.externalLinkName(for: symID) == "kk_sequence_chunked_transform"
            }
            if !alreadyRegistered {
                let chunkedSymbol = symbols.define(
                    kind: .function,
                    name: chunkedName,
                    fqName: chunkedFQName,
                    declSite: nil,
                    visibility: .public,
                    flags: [.synthetic, .inlineFunction]
                )
                symbols.setParentSymbol(sequenceSymbol, for: chunkedSymbol)
                symbols.setExternalLinkName("kk_sequence_chunked_transform", for: chunkedSymbol)
                let receiverType = types.make(.classType(ClassType(
                    classSymbol: sequenceSymbol,
                    args: [.out(seqTypeParamType)],
                    nullability: .nonNull
                )))
                symbols.setFunctionSignature(
                    FunctionSignature(
                        receiverType: receiverType,
                        parameterTypes: [types.intType, transformType],
                        returnType: sequenceReturnType,
                        typeParameterSymbols: [seqTypeParamSymbol],
                        classTypeParameterCount: 1
                    ),
                    for: chunkedSymbol
                )
            }
        }

        return sequenceSymbol
    }

    /// Register `Iterable<E>.asSequence(): Sequence<E>` member stub (STDLIB-555).
    ///
    /// Kotlin defines `asSequence()` on `Iterable<T>`, so any receiver typed as
    /// `Iterable` (not just `List` or `Array`) should resolve this member.  At
    /// runtime we delegate to `kk_iterable_asSequence` which handles any
    /// collection handle (List, Set, Array) via `runtimeCollectionElements`.
    private func registerIterableAsSequenceMember(
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner,
        kotlinCollectionsPkg: [InternedString],
        iterableInterfaceSymbol: SymbolID
    ) {
        guard let iterableFQName = symbols.symbol(iterableInterfaceSymbol)?.fqName else { return }
        let memberName = interner.intern("asSequence")
        let memberFQName = iterableFQName + [memberName]
        guard symbols.lookup(fqName: memberFQName) == nil else { return }

        // Retrieve the type parameter E from Iterable<E>.
        let typeParamName = interner.intern("E")
        let typeParamFQName = iterableFQName + [typeParamName]
        guard let typeParamSymbol = symbols.lookup(fqName: typeParamFQName) else { return }
        let typeParamType = types.make(.typeParam(TypeParamType(
            symbol: typeParamSymbol, nullability: .nonNull
        )))

        let receiverType = types.make(.classType(ClassType(
            classSymbol: iterableInterfaceSymbol,
            args: [.out(typeParamType)],
            nullability: .nonNull
        )))

        // Return type is Sequence<E> — ensure the Sequence interface stub exists.
        let sequenceSymbol = ensureSyntheticSequenceStub(
            symbols: symbols,
            types: types,
            interner: interner,
            kotlinCollectionsPkg: kotlinCollectionsPkg
        )
        let returnType = types.make(.classType(ClassType(
            classSymbol: sequenceSymbol,
            args: [.out(typeParamType)],
            nullability: .nonNull
        )))
        let memberSymbol = symbols.define(
            kind: .function,
            name: memberName,
            fqName: memberFQName,
            declSite: nil,
            visibility: .public,
            flags: [.synthetic]
        )
        symbols.setParentSymbol(iterableInterfaceSymbol, for: memberSymbol)
        // At runtime, use kk_iterable_asSequence which handles List, Set, and Array handles.
        // The corresponding ExternDecl is exposed via RuntimeABIExterns and
        // it is registered as non-throwing in ABILoweringPass+NonThrowingCallees.swift.
        symbols.setExternalLinkName("kk_iterable_asSequence", for: memberSymbol)
        symbols.setFunctionSignature(
            FunctionSignature(
                receiverType: receiverType,
                parameterTypes: [],
                returnType: returnType,
                typeParameterSymbols: [typeParamSymbol],
                classTypeParameterCount: 1
            ),
            for: memberSymbol
        )
    }

    /// Register `Iterable<E>.firstNotNullOfOrNull(transform)` (STDLIB-COL-HOF-002).
    private func registerIterableFirstNotNullOfOrNullMember(
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner,
        iterableInterfaceSymbol: SymbolID
    ) {
        guard let iterableFQName = symbols.symbol(iterableInterfaceSymbol)?.fqName,
              let iterableTypeParamSymbol = types.nominalTypeParameterSymbols(for: iterableInterfaceSymbol).first
        else { return }

        let memberName = interner.intern("firstNotNullOfOrNull")
        let memberFQName = iterableFQName + [memberName]
        let resultTypeParamName = interner.intern("R")
        let resultTypeParamSymbol = symbols.define(
            kind: .typeParameter,
            name: resultTypeParamName,
            fqName: memberFQName + [resultTypeParamName],
            declSite: nil,
            visibility: .private,
            flags: []
        )
        let elementType = types.make(.typeParam(TypeParamType(
            symbol: iterableTypeParamSymbol,
            nullability: .nonNull
        )))
        let resultType = types.make(.typeParam(TypeParamType(
            symbol: resultTypeParamSymbol,
            nullability: .nullable
        )))
        let receiverType = types.make(.classType(ClassType(
            classSymbol: iterableInterfaceSymbol,
            args: [.out(elementType)],
            nullability: .nonNull
        )))
        let transformType = types.make(.functionType(FunctionType(
            params: [elementType],
            returnType: resultType,
            isSuspend: false,
            nullability: .nonNull
        )))

        let alreadyRegistered = symbols.lookupAll(fqName: memberFQName).contains { symbolID in
            guard let sig = symbols.functionSignature(for: symbolID) else { return false }
            return sig.parameterTypes == [transformType]
        }
        guard !alreadyRegistered else { return }

        let memberSymbol = symbols.define(
            kind: .function,
            name: memberName,
            fqName: memberFQName,
            declSite: nil,
            visibility: .public,
            flags: [.synthetic, .inlineFunction]
        )
        symbols.setParentSymbol(iterableInterfaceSymbol, for: memberSymbol)
        symbols.setExternalLinkName("kk_iterable_firstNotNullOfOrNull", for: memberSymbol)
        symbols.setFunctionSignature(
            FunctionSignature(
                receiverType: receiverType,
                parameterTypes: [transformType],
                returnType: resultType,
                typeParameterSymbols: [iterableTypeParamSymbol, resultTypeParamSymbol],
                classTypeParameterCount: 1
            ),
            for: memberSymbol
        )
    }

    /// Register `Iterable<E>.windowed(size, step, partialWindows, transform)` HOF overload (STDLIB-COL-WIN-001).
    ///
    /// Kotlin signature:
    /// `fun <T, R> Iterable<T>.windowed(size: Int, step: Int = 1, partialWindows: Boolean = false, transform: (List<T>) -> R): List<R>`
    ///
    /// The runtime ABI erases `R`, so the return type is modeled as `List<Any>`.
    private func registerIterableWindowedTransformMember(
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner,
        kotlinCollectionsPkg: [InternedString],
        iterableInterfaceSymbol: SymbolID,
        listInterfaceSymbol: SymbolID
    ) {
        guard let iterableFQName = symbols.symbol(iterableInterfaceSymbol)?.fqName else { return }
        let memberName = interner.intern("windowed")
        let memberFQName = iterableFQName + [memberName]
        guard symbols.lookup(fqName: memberFQName) == nil else { return }

        let listFQName = symbols.symbol(listInterfaceSymbol)?.fqName ?? kotlinCollectionsPkg + [interner.intern("List")]
        let listTypeParamFQName = listFQName + [interner.intern("E")]
        guard let listTypeParamSymbol = symbols.lookup(fqName: listTypeParamFQName) else { return }
        let listTypeParamType = types.make(.typeParam(TypeParamType(
            symbol: listTypeParamSymbol,
            nullability: .nonNull
        )))

        let receiverType = types.make(.classType(ClassType(
            classSymbol: iterableInterfaceSymbol,
            args: [.out(listTypeParamType)],
            nullability: .nonNull
        )))
        let transformParameterType = types.make(.classType(ClassType(
            classSymbol: listInterfaceSymbol,
            args: [.invariant(listTypeParamType)],
            nullability: .nonNull
        )))
        let transformType = types.make(.functionType(FunctionType(
            params: [transformParameterType],
            returnType: types.anyType,
            isSuspend: false,
            nullability: .nonNull
        )))
        let listOfAnyReturnType = types.make(.classType(ClassType(
            classSymbol: listInterfaceSymbol,
            args: [.out(types.anyType)],
            nullability: .nonNull
        )))

        func registerWindowedTransformOverload(_ parameterTypes: [TypeID]) {
            let existingOverloads = symbols.lookupAll(fqName: memberFQName)
            let alreadyRegistered = existingOverloads.contains { symID in
                guard let sig = symbols.functionSignature(for: symID) else { return false }
                return sig.parameterTypes == parameterTypes
                    && symbols.externalLinkName(for: symID) == "kk_list_windowed_transform"
            }
            guard !alreadyRegistered else { return }
            let memberSymbol = symbols.define(
                kind: .function,
                name: memberName,
                fqName: memberFQName,
                declSite: nil,
                visibility: .public,
                flags: [.synthetic, .inlineFunction]
            )
            symbols.setParentSymbol(iterableInterfaceSymbol, for: memberSymbol)
            symbols.setExternalLinkName("kk_list_windowed_transform", for: memberSymbol)
            symbols.setFunctionSignature(
                FunctionSignature(
                    receiverType: receiverType,
                    parameterTypes: parameterTypes,
                    returnType: listOfAnyReturnType,
                    typeParameterSymbols: [listTypeParamSymbol],
                    classTypeParameterCount: 1
                ),
                for: memberSymbol
            )
        }

        registerWindowedTransformOverload([types.intType, transformType])
        registerWindowedTransformOverload([types.intType, types.intType, transformType])
        registerWindowedTransformOverload([types.intType, types.intType, types.booleanType, transformType])
    }

    /// Register `Iterable<E>.firstNotNullOf(transform)` (STDLIB-COL-HOF-001).
    private func registerIterableFirstNotNullOfMember(
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner,
        iterableInterfaceSymbol: SymbolID
    ) {
        guard let iterableFQName = symbols.symbol(iterableInterfaceSymbol)?.fqName,
              let iterableTypeParamSymbol = types.nominalTypeParameterSymbols(for: iterableInterfaceSymbol).first
        else { return }

        let memberName = interner.intern("firstNotNullOf")
        let memberFQName = iterableFQName + [memberName]
        let resultTypeParamName = interner.intern("R")
        let resultTypeParamSymbol = symbols.define(
            kind: .typeParameter,
            name: resultTypeParamName,
            fqName: memberFQName + [resultTypeParamName],
            declSite: nil,
            visibility: .private,
            flags: []
        )
        let elementType = types.make(.typeParam(TypeParamType(
            symbol: iterableTypeParamSymbol,
            nullability: .nonNull
        )))
        let resultType = types.make(.typeParam(TypeParamType(
            symbol: resultTypeParamSymbol,
            nullability: .nonNull
        )))
        let nullableResultType = types.make(.typeParam(TypeParamType(
            symbol: resultTypeParamSymbol,
            nullability: .nullable
        )))
        let receiverType = types.make(.classType(ClassType(
            classSymbol: iterableInterfaceSymbol,
            args: [.out(elementType)],
            nullability: .nonNull
        )))
        let transformType = types.make(.functionType(FunctionType(
            params: [elementType],
            returnType: nullableResultType,
            isSuspend: false,
            nullability: .nonNull
        )))

        let alreadyRegistered = symbols.lookupAll(fqName: memberFQName).contains { symbolID in
            guard let sig = symbols.functionSignature(for: symbolID) else { return false }
            return sig.parameterTypes == [transformType]
        }
        guard !alreadyRegistered else { return }

        let memberSymbol = symbols.define(
            kind: .function,
            name: memberName,
            fqName: memberFQName,
            declSite: nil,
            visibility: .public,
            flags: [.synthetic, .inlineFunction]
        )
        symbols.setParentSymbol(iterableInterfaceSymbol, for: memberSymbol)
        symbols.setExternalLinkName("kk_iterable_firstNotNullOf", for: memberSymbol)
        symbols.setFunctionSignature(
            FunctionSignature(
                receiverType: receiverType,
                parameterTypes: [transformType],
                returnType: resultType,
                typeParameterSymbols: [iterableTypeParamSymbol, resultTypeParamSymbol],
                classTypeParameterCount: 1
            ),
            for: memberSymbol
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
