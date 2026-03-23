// swiftlint:disable file_length
import Foundation

/// Centralized FQ-name suffix used to discriminate the comparison-based
/// `binarySearch` overload from the element-based one.
private let binarySearchCompareFQSuffix = "binarySearch$compare"

extension DataFlowSemaPhase {
    /// Register `kotlin.Comparable<T>` interface stub with `operator fun compareTo(other: T): Int`.
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

        // Define type parameter T for Comparable<T>
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
    }

    /// Register `operator fun compareTo(other: T): Int` on the Comparable interface.
    private func registerComparableCompareToOperator(
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner,
        comparableFQName: [InternedString],
        comparableSymbol: SymbolID,
        tParamSymbol: SymbolID,
        tParamType: TypeID
    ) {
        let compareToName = interner.intern("compareTo")
        let compareToFQName = comparableFQName + [compareToName]
        guard symbols.lookup(fqName: compareToFQName) == nil else { return }
        let receiverType = types.make(.classType(ClassType(
            classSymbol: comparableSymbol,
            args: [.invariant(tParamType)],
            nullability: .nonNull
        )))
        let compareToSymbol = symbols.define(
            kind: .function,
            name: compareToName,
            fqName: compareToFQName,
            declSite: nil,
            visibility: .public,
            flags: [.synthetic, .operatorFunction]
        )
        symbols.setParentSymbol(comparableSymbol, for: compareToSymbol)
        symbols.setFunctionSignature(
            FunctionSignature(
                receiverType: receiverType,
                parameterTypes: [tParamType],
                returnType: types.intType,
                typeParameterSymbols: [tParamSymbol],
                classTypeParameterCount: 1
            ),
            for: compareToSymbol
        )
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

        let collectionInterfaceSymbol = registerSyntheticCollectionStub(
            symbols: symbols, types: types, interner: interner,
            kotlinCollectionsPkg: kotlinCollectionsPkg,
            iterableInterfaceSymbol: iterableInterfaceSymbol
        )

        let listInterfaceSymbol = registerSyntheticListStub(
            symbols: symbols, types: types, interner: interner,
            kotlinCollectionsPkg: kotlinCollectionsPkg,
            collectionInterfaceSymbol: collectionInterfaceSymbol
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
            collectionInterfaceSymbol: collectionInterfaceSymbol
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
            collectionInterfaceSymbol: collectionInterfaceSymbol
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

        // Register Array<T> and primitive array types (TYPE-103)
        registerSyntheticArrayStubs(
            symbols: symbols, types: types, interner: interner
        )

        // Register type aliases: ArrayList, HashMap, HashSet, LinkedHashMap, LinkedHashSet (STDLIB-560)
        // TODO: Add golden test cases that exercise these aliases in type positions
        //       (e.g. property types, parameter types, return types) to verify
        //       resolveTypeRef expansion works end-to-end.
        registerSyntheticCollectionTypeAliases(
            symbols: symbols, types: types, interner: interner,
            kotlinCollectionsPkg: kotlinCollectionsPkg
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

        // Pair<A,B>.toList() returns List<Any?> in Kotlin (elements can be nullable).
        // The List symbol is registered after Pair, so we initially use nullable anyType
        // as a placeholder; patchPairTripleToListReturnTypes() refines this to List<Any?>.
        registerFunctionMember(
            name: "toList",
            returnType: types.makeNullable(types.anyType),
            externalLinkName: "kk_pair_toList",
            flags: [.synthetic]
        )

        // Register Pair(first, second) constructor
        do {
            let initName = interner.intern("<init>")
            let ctorFQName = pairFQName + [initName]
            if symbols.lookupAll(fqName: ctorFQName).isEmpty {
                let ctorSymbol = symbols.define(
                    kind: .constructor,
                    name: initName,
                    fqName: ctorFQName,
                    declSite: nil,
                    visibility: .public,
                    flags: [.synthetic]
                )
                symbols.setParentSymbol(pairSymbol, for: ctorSymbol)
                symbols.setExternalLinkName("kk_pair_new", for: ctorSymbol)
                let firstParamName = interner.intern("first")
                let secondParamName = interner.intern("second")
                let firstParam = symbols.define(
                    kind: .valueParameter, name: firstParamName,
                    fqName: ctorFQName + [firstParamName],
                    declSite: nil, visibility: .private, flags: [.synthetic]
                )
                symbols.setParentSymbol(ctorSymbol, for: firstParam)
                let secondParam = symbols.define(
                    kind: .valueParameter, name: secondParamName,
                    fqName: ctorFQName + [secondParamName],
                    declSite: nil, visibility: .private, flags: [.synthetic]
                )
                symbols.setParentSymbol(ctorSymbol, for: secondParam)
                symbols.setFunctionSignature(
                    FunctionSignature(
                        parameterTypes: [firstType, secondType],
                        returnType: pairType,
                        valueParameterSymbols: [firstParam, secondParam],
                        valueParameterHasDefaultValues: [false, false],
                        valueParameterIsVararg: [false, false],
                        typeParameterSymbols: [firstSymbol, secondSymbol],
                        classTypeParameterCount: 2
                    ),
                    for: ctorSymbol
                )
            }
        }
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

        registerFunctionMember(name: "component1", returnType: aType, externalLinkName: "kk_triple_first", flags: [.synthetic, .operatorFunction])
        registerFunctionMember(name: "component2", returnType: bType, externalLinkName: "kk_triple_second", flags: [.synthetic, .operatorFunction])
        registerFunctionMember(name: "component3", returnType: cType, externalLinkName: "kk_triple_third", flags: [.synthetic, .operatorFunction])
        registerPropertyMember(name: "first", propertyType: aType, externalLinkName: "kk_triple_first")
        registerPropertyMember(name: "second", propertyType: bType, externalLinkName: "kk_triple_second")
        registerPropertyMember(name: "third", propertyType: cType, externalLinkName: "kk_triple_third")
        // Triple<A,B,C>.toList() returns List<Any?> in Kotlin (elements can be nullable).
        // The List symbol is registered after Triple, so we initially use nullable anyType
        // as a placeholder; patchPairTripleToListReturnTypes() refines this to List<Any?>.
        registerFunctionMember(name: "toList", returnType: types.makeNullable(types.anyType), externalLinkName: "kk_triple_toList", flags: [.synthetic])

        // Register Triple(first, second, third) constructor
        do {
            let initName = interner.intern("<init>")
            let ctorFQName = tripleFQName + [initName]
            if symbols.lookupAll(fqName: ctorFQName).isEmpty {
                let ctorSymbol = symbols.define(
                    kind: .constructor,
                    name: initName,
                    fqName: ctorFQName,
                    declSite: nil,
                    visibility: .public,
                    flags: [.synthetic]
                )
                symbols.setParentSymbol(tripleSymbol, for: ctorSymbol)
                symbols.setExternalLinkName("kk_triple_new", for: ctorSymbol)
                let firstParamName = interner.intern("first")
                let secondParamName = interner.intern("second")
                let thirdParamName = interner.intern("third")
                let firstParam = symbols.define(
                    kind: .valueParameter, name: firstParamName,
                    fqName: ctorFQName + [firstParamName],
                    declSite: nil, visibility: .private, flags: [.synthetic]
                )
                symbols.setParentSymbol(ctorSymbol, for: firstParam)
                let secondParam = symbols.define(
                    kind: .valueParameter, name: secondParamName,
                    fqName: ctorFQName + [secondParamName],
                    declSite: nil, visibility: .private, flags: [.synthetic]
                )
                symbols.setParentSymbol(ctorSymbol, for: secondParam)
                let thirdParam = symbols.define(
                    kind: .valueParameter, name: thirdParamName,
                    fqName: ctorFQName + [thirdParamName],
                    declSite: nil, visibility: .private, flags: [.synthetic]
                )
                symbols.setParentSymbol(ctorSymbol, for: thirdParam)
                symbols.setFunctionSignature(
                    FunctionSignature(
                        parameterTypes: [aType, bType, cType],
                        returnType: tripleType,
                        valueParameterSymbols: [firstParam, secondParam, thirdParam],
                        valueParameterHasDefaultValues: [false, false, false],
                        valueParameterIsVararg: [false, false, false],
                        typeParameterSymbols: [aSymbol, bSymbol, cSymbol],
                        classTypeParameterCount: 3
                    ),
                    for: ctorSymbol
                )
            }
        }
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

    /// Register `Collection<E>.toList(): List<E>` so that `keys.toList()` / `values.toList()` resolve.
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

        // Iterator.hasNext(): Boolean
        let hasNextName = interner.intern("hasNext")
        let hasNextFQName = iteratorFQName + [hasNextName]
        if symbols.lookup(fqName: hasNextFQName) == nil {
            let sym = symbols.define(
                kind: .function, name: hasNextName, fqName: hasNextFQName,
                declSite: nil, visibility: .public, flags: [.synthetic]
            )
            symbols.setPropertyType(types.make(.functionType(FunctionType(
                params: [], returnType: types.booleanType, isSuspend: false, nullability: .nonNull
            ))), for: sym)
        }

        // Iterator.next(): T
        let nextName = interner.intern("next")
        let nextFQName = iteratorFQName + [nextName]
        if symbols.lookup(fqName: nextFQName) == nil {
            let itTypeParamType = types.make(.typeParam(TypeParamType(symbol: itTypeParamSymbol, nullability: .nonNull)))
            let sym = symbols.define(
                kind: .function, name: nextName, fqName: nextFQName,
                declSite: nil, visibility: .public, flags: [.synthetic]
            )
            symbols.setPropertyType(types.make(.functionType(FunctionType(
                params: [], returnType: itTypeParamType, isSuspend: false, nullability: .nonNull
            ))), for: sym)
        }

        // MutableIterator<T> : Iterator<T> (STDLIB-221)
        let mutableIteratorName = interner.intern("MutableIterator")
        let mutableIteratorFQName = kotlinCollectionsPkg + [mutableIteratorName]
        if symbols.lookup(fqName: mutableIteratorFQName) == nil {
            let mutIterSym = symbols.define(
                kind: .interface, name: mutableIteratorName, fqName: mutableIteratorFQName,
                declSite: nil, visibility: .public, flags: [.synthetic]
            )
            symbols.setDirectSupertypes([iteratorSymbol], for: mutIterSym)
            types.setNominalDirectSupertypes([iteratorSymbol], for: mutIterSym)

            // MutableIterator.remove(): Unit
            let removeName = interner.intern("remove")
            let removeFQName = mutableIteratorFQName + [removeName]
            let removeSym = symbols.define(
                kind: .function, name: removeName, fqName: removeFQName,
                declSite: nil, visibility: .public, flags: [.synthetic]
            )
            symbols.setPropertyType(types.make(.functionType(FunctionType(
                params: [], returnType: types.unitType, isSuspend: false, nullability: .nonNull
            ))), for: removeSym)
        }

        return iterableInterfaceSymbol
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
        // The corresponding ExternDecl is in RuntimeABIExterns+Collection.swift and
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
    private func registerSyntheticListStub(
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner,
        kotlinCollectionsPkg: [InternedString],
        collectionInterfaceSymbol: SymbolID
    ) -> SymbolID {
        let listName = interner.intern("List")
        let listFQName = kotlinCollectionsPkg + [listName]
        let listInterfaceSymbol: SymbolID = if let existing = symbols.lookup(fqName: listFQName) {
            existing
        } else {
            symbols.define(
                kind: .interface,
                name: listName,
                fqName: listFQName,
                declSite: nil,
                visibility: .public,
                flags: [.synthetic]
            )
        }

        // Define type parameter E for List<E>
        let listTypeParamName = interner.intern("E")
        let listTypeParamFQName = listFQName + [listTypeParamName]
        let listTypeParamSymbol = symbols.define(
            kind: .typeParameter,
            name: listTypeParamName,
            fqName: listTypeParamFQName,
            declSite: nil,
            visibility: .private,
            flags: []
        )
        let listTypeParamType = types.make(.typeParam(TypeParamType(
            symbol: listTypeParamSymbol, nullability: .nonNull
        )))
        types.setNominalTypeParameterSymbols([listTypeParamSymbol], for: listInterfaceSymbol)
        types.setNominalTypeParameterVariances([.out], for: listInterfaceSymbol)
        symbols.setDirectSupertypes([collectionInterfaceSymbol], for: listInterfaceSymbol)
        types.setNominalDirectSupertypes([collectionInterfaceSymbol], for: listInterfaceSymbol)
        symbols.setSupertypeTypeArgs([.out(listTypeParamType)], for: listInterfaceSymbol, supertype: collectionInterfaceSymbol)
        types.setNominalSupertypeTypeArgs([.out(listTypeParamType)], for: listInterfaceSymbol, supertype: collectionInterfaceSymbol)

        registerListGetOperator(
            symbols: symbols, types: types, interner: interner,
            listFQName: listFQName,
            listInterfaceSymbol: listInterfaceSymbol,
            listTypeParamSymbol: listTypeParamSymbol,
            listTypeParamType: listTypeParamType
        )
        registerListContainsAndIsEmptyMembers(
            symbols: symbols, types: types, interner: interner,
            listFQName: listFQName,
            listInterfaceSymbol: listInterfaceSymbol,
            listTypeParamSymbol: listTypeParamSymbol,
            listTypeParamType: listTypeParamType,
            collectionInterfaceSymbol: collectionInterfaceSymbol
        )
        registerListJoinToStringMember(
            symbols: symbols, types: types, interner: interner,
            listFQName: listFQName,
            listInterfaceSymbol: listInterfaceSymbol,
            listTypeParamSymbol: listTypeParamSymbol,
            listTypeParamType: listTypeParamType
        )
        registerListContentEqualsMember(
            symbols: symbols, types: types, interner: interner,
            listFQName: listFQName,
            listInterfaceSymbol: listInterfaceSymbol,
            listTypeParamSymbol: listTypeParamSymbol,
            listTypeParamType: listTypeParamType
        )
        registerListTransformMembers(
            symbols: symbols, types: types, interner: interner,
            listFQName: listFQName,
            listInterfaceSymbol: listInterfaceSymbol,
            listTypeParamSymbol: listTypeParamSymbol,
            listTypeParamType: listTypeParamType
        )
        registerListAggregateMembers(
            symbols: symbols, types: types, interner: interner,
            listFQName: listFQName,
            listInterfaceSymbol: listInterfaceSymbol,
            listTypeParamSymbol: listTypeParamSymbol,
            listTypeParamType: listTypeParamType
        )
        registerListIteratorMember(
            symbols: symbols, types: types, interner: interner,
            kotlinCollectionsPkg: kotlinCollectionsPkg,
            listFQName: listFQName,
            listInterfaceSymbol: listInterfaceSymbol,
            listTypeParamSymbol: listTypeParamSymbol,
            listTypeParamType: listTypeParamType
        )
        return listInterfaceSymbol
    }

    /// Register `operator fun get(index: Int): E` on the List interface.
    private func registerListGetOperator(
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner,
        listFQName: [InternedString],
        listInterfaceSymbol: SymbolID,
        listTypeParamSymbol: SymbolID,
        listTypeParamType: TypeID
    ) {
        let listGetName = interner.intern("get")
        let listGetFQName = listFQName + [listGetName]
        guard symbols.lookup(fqName: listGetFQName) == nil else { return }
        let listReceiverType = types.make(.classType(ClassType(
            classSymbol: listInterfaceSymbol,
            args: [.out(listTypeParamType)],
            nullability: .nonNull
        )))
        let listGetSymbol = symbols.define(
            kind: .function,
            name: listGetName,
            fqName: listGetFQName,
            declSite: nil,
            visibility: .public,
            flags: [.synthetic, .operatorFunction]
        )
        symbols.setParentSymbol(listInterfaceSymbol, for: listGetSymbol)
        symbols.setExternalLinkName("kk_list_get", for: listGetSymbol)
        symbols.setFunctionSignature(
            FunctionSignature(
                receiverType: listReceiverType,
                parameterTypes: [types.intType],
                returnType: listTypeParamType,
                typeParameterSymbols: [listTypeParamSymbol],
                classTypeParameterCount: 1
            ),
            for: listGetSymbol
        )
    }

    /// STDLIB-538: Register `ListIterator<T>` interface extending `Iterator<T>`,
    /// with `hasPrevious(): Boolean` and `previous(): T` members.
    private func ensureSyntheticListIteratorStub(
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner,
        kotlinCollectionsPkg: [InternedString]
    ) -> SymbolID {
        let listIteratorName = interner.intern("ListIterator")
        let listIteratorFQName = kotlinCollectionsPkg + [listIteratorName]
        if let existing = symbols.lookup(fqName: listIteratorFQName) {
            return existing
        }

        // Look up the parent Iterator<T> symbol.
        let iteratorName = interner.intern("Iterator")
        let iteratorFQName = kotlinCollectionsPkg + [iteratorName]
        let iteratorSymbol = symbols.lookup(fqName: iteratorFQName)

        let listIteratorSymbol = symbols.define(
            kind: .interface,
            name: listIteratorName,
            fqName: listIteratorFQName,
            declSite: nil,
            visibility: .public,
            flags: [.synthetic]
        )

        // Type parameter T
        let tpName = interner.intern("T")
        let tpFQName = listIteratorFQName + [tpName]
        let tpSymbol = symbols.define(
            kind: .typeParameter,
            name: tpName,
            fqName: tpFQName,
            declSite: nil,
            visibility: .private,
            flags: []
        )
        let tpType = types.make(.typeParam(TypeParamType(symbol: tpSymbol, nullability: .nonNull)))
        types.setNominalTypeParameterSymbols([tpSymbol], for: listIteratorSymbol)
        types.setNominalTypeParameterVariances([.out], for: listIteratorSymbol)

        // Supertype: Iterator<T>
        if let iteratorSymbol {
            symbols.setDirectSupertypes([iteratorSymbol], for: listIteratorSymbol)
            types.setNominalDirectSupertypes([iteratorSymbol], for: listIteratorSymbol)
            symbols.setSupertypeTypeArgs([.out(tpType)], for: listIteratorSymbol, supertype: iteratorSymbol)
            types.setNominalSupertypeTypeArgs([.out(tpType)], for: listIteratorSymbol, supertype: iteratorSymbol)
        }

        let listIteratorReceiverType = types.make(.classType(ClassType(
            classSymbol: listIteratorSymbol,
            args: [.out(tpType)],
            nullability: .nonNull
        )))

        // hasNext(): Boolean (inherited from Iterator, registered for member resolution)
        let hasNextName = interner.intern("hasNext")
        let hasNextFQName = listIteratorFQName + [hasNextName]
        if symbols.lookup(fqName: hasNextFQName) == nil {
            let hasNextSym = symbols.define(
                kind: .function, name: hasNextName, fqName: hasNextFQName,
                declSite: nil, visibility: .public, flags: [.synthetic]
            )
            symbols.setParentSymbol(listIteratorSymbol, for: hasNextSym)
            symbols.setPropertyType(types.make(.functionType(FunctionType(
                params: [], returnType: types.booleanType, isSuspend: false, nullability: .nonNull
            ))), for: hasNextSym)
            symbols.setExternalLinkName("kk_list_iterator_hasNext", for: hasNextSym)
            symbols.setFunctionSignature(
                FunctionSignature(
                    receiverType: listIteratorReceiverType,
                    parameterTypes: [],
                    returnType: types.booleanType,
                    typeParameterSymbols: [tpSymbol],
                    classTypeParameterCount: 1
                ),
                for: hasNextSym
            )
        }

        // next(): T (inherited from Iterator, registered for member resolution)
        let nextName = interner.intern("next")
        let nextFQName = listIteratorFQName + [nextName]
        if symbols.lookup(fqName: nextFQName) == nil {
            let nextSym = symbols.define(
                kind: .function, name: nextName, fqName: nextFQName,
                declSite: nil, visibility: .public, flags: [.synthetic]
            )
            symbols.setParentSymbol(listIteratorSymbol, for: nextSym)
            symbols.setPropertyType(types.make(.functionType(FunctionType(
                params: [], returnType: tpType, isSuspend: false, nullability: .nonNull
            ))), for: nextSym)
            symbols.setExternalLinkName("kk_list_iterator_next", for: nextSym)
            symbols.setFunctionSignature(
                FunctionSignature(
                    receiverType: listIteratorReceiverType,
                    parameterTypes: [],
                    returnType: tpType,
                    typeParameterSymbols: [tpSymbol],
                    classTypeParameterCount: 1
                ),
                for: nextSym
            )
        }

        // hasPrevious(): Boolean
        let hasPreviousName = interner.intern("hasPrevious")
        let hasPreviousFQName = listIteratorFQName + [hasPreviousName]
        let hasPreviousSym = symbols.define(
            kind: .function, name: hasPreviousName, fqName: hasPreviousFQName,
            declSite: nil, visibility: .public, flags: [.synthetic]
        )
        symbols.setParentSymbol(listIteratorSymbol, for: hasPreviousSym)
        symbols.setPropertyType(types.make(.functionType(FunctionType(
            params: [], returnType: types.booleanType, isSuspend: false, nullability: .nonNull
        ))), for: hasPreviousSym)
        symbols.setExternalLinkName("kk_list_iterator_hasPrevious", for: hasPreviousSym)
        symbols.setFunctionSignature(
            FunctionSignature(
                receiverType: listIteratorReceiverType,
                parameterTypes: [],
                returnType: types.booleanType,
                typeParameterSymbols: [tpSymbol],
                classTypeParameterCount: 1
            ),
            for: hasPreviousSym
        )

        // previous(): T
        let previousName = interner.intern("previous")
        let previousFQName = listIteratorFQName + [previousName]
        let previousSym = symbols.define(
            kind: .function, name: previousName, fqName: previousFQName,
            declSite: nil, visibility: .public, flags: [.synthetic]
        )
        symbols.setParentSymbol(listIteratorSymbol, for: previousSym)
        symbols.setPropertyType(types.make(.functionType(FunctionType(
            params: [], returnType: tpType, isSuspend: false, nullability: .nonNull
        ))), for: previousSym)
        symbols.setExternalLinkName("kk_list_iterator_previous", for: previousSym)
        symbols.setFunctionSignature(
            FunctionSignature(
                receiverType: listIteratorReceiverType,
                parameterTypes: [],
                returnType: tpType,
                typeParameterSymbols: [tpSymbol],
                classTypeParameterCount: 1
            ),
            for: previousSym
        )

        return listIteratorSymbol
    }

    /// STDLIB-538: Register `List<E>.listIterator(): ListIterator<E>`.
    private func registerListIteratorMember(
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner,
        kotlinCollectionsPkg: [InternedString],
        listFQName: [InternedString],
        listInterfaceSymbol: SymbolID,
        listTypeParamSymbol: SymbolID,
        listTypeParamType: TypeID
    ) {
        let listIteratorInterfaceSymbol = ensureSyntheticListIteratorStub(
            symbols: symbols, types: types, interner: interner,
            kotlinCollectionsPkg: kotlinCollectionsPkg
        )

        let memberName = interner.intern("listIterator")
        let memberFQName = listFQName + [memberName]
        guard symbols.lookup(fqName: memberFQName) == nil else { return }

        let listReceiverType = types.make(.classType(ClassType(
            classSymbol: listInterfaceSymbol,
            args: [.out(listTypeParamType)],
            nullability: .nonNull
        )))
        let returnType = types.make(.classType(ClassType(
            classSymbol: listIteratorInterfaceSymbol,
            args: [.out(listTypeParamType)],
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
        symbols.setParentSymbol(listInterfaceSymbol, for: memberSymbol)
        symbols.setExternalLinkName("kk_list_iterator", for: memberSymbol)
        symbols.setPropertyType(types.make(.functionType(FunctionType(
            params: [], returnType: returnType, isSuspend: false, nullability: .nonNull
        ))), for: memberSymbol)
        symbols.setFunctionSignature(
            FunctionSignature(
                receiverType: listReceiverType,
                parameterTypes: [],
                returnType: returnType,
                typeParameterSymbols: [listTypeParamSymbol],
                classTypeParameterCount: 1
            ),
            for: memberSymbol
        )
    }

    /// STDLIB-183: List<T>.component1() ~ component5() for destructuring.
    private func registerListComponentNMembers(
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner,
        listFQName: [InternedString],
        listInterfaceSymbol: SymbolID,
        listTypeParamSymbol: SymbolID,
        listTypeParamType: TypeID
    ) {
        let listReceiverType = types.make(.classType(ClassType(
            classSymbol: listInterfaceSymbol,
            args: [.out(listTypeParamType)],
            nullability: .nonNull
        )))
        let componentNames = ["component1", "component2", "component3", "component4", "component5"]
        let externalLinkNames = [
            "kk_list_component1", "kk_list_component2", "kk_list_component3",
            "kk_list_component4", "kk_list_component5",
        ]
        for (componentName, externalLinkName) in zip(componentNames, externalLinkNames) {
            let name = interner.intern(componentName)
            let fqName = listFQName + [name]
            guard symbols.lookupAll(fqName: fqName).first(where: { symbolID in
                guard let sig = symbols.functionSignature(for: symbolID) else { return false }
                return sig.receiverType == listReceiverType && sig.parameterTypes.isEmpty
            }) == nil else { continue }
            let memberSymbol = symbols.define(
                kind: .function,
                name: name,
                fqName: fqName,
                declSite: nil,
                visibility: .public,
                flags: [.synthetic, .operatorFunction]
            )
            symbols.setParentSymbol(listInterfaceSymbol, for: memberSymbol)
            symbols.setExternalLinkName(externalLinkName, for: memberSymbol)
            symbols.setFunctionSignature(
                FunctionSignature(
                    receiverType: listReceiverType,
                    parameterTypes: [],
                    returnType: listTypeParamType,
                    typeParameterSymbols: [listTypeParamSymbol],
                    classTypeParameterCount: 1
                ),
                for: memberSymbol
            )
        }
    }

    private func registerListContainsAndIsEmptyMembers(
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner,
        listFQName: [InternedString],
        listInterfaceSymbol: SymbolID,
        listTypeParamSymbol: SymbolID,
        listTypeParamType: TypeID,
        collectionInterfaceSymbol: SymbolID
    ) {
        let listReceiverType = types.make(.classType(ClassType(
            classSymbol: listInterfaceSymbol,
            args: [.out(listTypeParamType)],
            nullability: .nonNull
        )))

        let containsName = interner.intern("contains")
        let containsFQName = listFQName + [containsName]
        if symbols.lookup(fqName: containsFQName) == nil {
            let containsSymbol = symbols.define(
                kind: .function,
                name: containsName,
                fqName: containsFQName,
                declSite: nil,
                visibility: .public,
                flags: [.synthetic, .operatorFunction]
            )
            symbols.setParentSymbol(listInterfaceSymbol, for: containsSymbol)
            symbols.setExternalLinkName("kk_list_contains", for: containsSymbol)
            symbols.setFunctionSignature(
                FunctionSignature(
                    receiverType: listReceiverType,
                    parameterTypes: [listTypeParamType],
                    returnType: types.booleanType,
                    typeParameterSymbols: [listTypeParamSymbol],
                    classTypeParameterCount: 1
                ),
                for: containsSymbol
            )
        }

        let containsAllName = interner.intern("containsAll")
        let containsAllFQName = listFQName + [containsAllName]
        if symbols.lookup(fqName: containsAllFQName) == nil {
            let containsAllSymbol = symbols.define(
                kind: .function,
                name: containsAllName,
                fqName: containsAllFQName,
                declSite: nil,
                visibility: .public,
                flags: [.synthetic]
            )
            symbols.setParentSymbol(listInterfaceSymbol, for: containsAllSymbol)
            symbols.setExternalLinkName("kk_list_containsAll", for: containsAllSymbol)
            let collectionParamType = types.make(.classType(ClassType(
                classSymbol: collectionInterfaceSymbol,
                args: [.out(listTypeParamType)],
                nullability: .nonNull
            )))
            symbols.setFunctionSignature(
                FunctionSignature(
                    receiverType: listReceiverType,
                    parameterTypes: [collectionParamType],
                    returnType: types.booleanType,
                    typeParameterSymbols: [listTypeParamSymbol],
                    classTypeParameterCount: 1
                ),
                for: containsAllSymbol
            )
        }

        let isEmptyName = interner.intern("isEmpty")
        let isEmptyFQName = listFQName + [isEmptyName]
        if symbols.lookup(fqName: isEmptyFQName) == nil {
            let isEmptySymbol = symbols.define(
                kind: .function,
                name: isEmptyName,
                fqName: isEmptyFQName,
                declSite: nil,
                visibility: .public,
                flags: [.synthetic]
            )
            symbols.setParentSymbol(listInterfaceSymbol, for: isEmptySymbol)
            symbols.setExternalLinkName("kk_list_is_empty", for: isEmptySymbol)
            symbols.setFunctionSignature(
                FunctionSignature(
                    receiverType: listReceiverType,
                    parameterTypes: [],
                    returnType: types.booleanType,
                    typeParameterSymbols: [listTypeParamSymbol],
                    classTypeParameterCount: 1
                ),
                for: isEmptySymbol
            )
        }

    }

    private func registerListToMutableListMember(
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner,
        listInterfaceSymbol: SymbolID,
        listTypeParamSymbol: SymbolID,
        listTypeParamType: TypeID,
        mutableListSymbol: SymbolID
    ) {
        guard let listFQName = symbols.symbol(listInterfaceSymbol)?.fqName else { return }
        let memberName = interner.intern("toMutableList")
        let memberFQName = listFQName + [memberName]
        guard symbols.lookup(fqName: memberFQName) == nil else { return }
        let receiverType = types.make(.classType(ClassType(
            classSymbol: listInterfaceSymbol,
            args: [.out(listTypeParamType)],
            nullability: .nonNull
        )))
        let mutableListType = types.make(.classType(ClassType(
            classSymbol: mutableListSymbol,
            args: [.invariant(listTypeParamType)],
            nullability: .nonNull
        )))
        let memberSymbol = symbols.define(
            kind: .function,
            name: memberName,
            fqName: memberFQName,
            declSite: nil,
            visibility: .public,
            flags: [.synthetic, .operatorFunction]
        )
        symbols.setParentSymbol(listInterfaceSymbol, for: memberSymbol)
        symbols.setExternalLinkName("kk_list_to_mutable_list", for: memberSymbol)
        symbols.setFunctionSignature(
            FunctionSignature(
                receiverType: receiverType,
                parameterTypes: [],
                returnType: mutableListType,
                typeParameterSymbols: [listTypeParamSymbol],
                classTypeParameterCount: 1
            ),
            for: memberSymbol
        )
    }

    private func registerListJoinToStringMember(
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner,
        listFQName: [InternedString],
        listInterfaceSymbol: SymbolID,
        listTypeParamSymbol: SymbolID,
        listTypeParamType: TypeID
    ) {
        let memberName = interner.intern("joinToString")
        let memberFQName = listFQName + [memberName]
        guard symbols.lookup(fqName: memberFQName) == nil else { return }

        let receiverType = types.make(.classType(ClassType(
            classSymbol: listInterfaceSymbol,
            args: [.out(listTypeParamType)],
            nullability: .nonNull
        )))
        let memberSymbol = symbols.define(
            kind: .function,
            name: memberName,
            fqName: memberFQName,
            declSite: nil,
            visibility: .public,
            flags: [.synthetic, .operatorFunction]
        )
        symbols.setParentSymbol(listInterfaceSymbol, for: memberSymbol)
        symbols.setExternalLinkName("kk_list_joinToString", for: memberSymbol)

        let parameters: [(name: String, type: TypeID, hasDefault: Bool)] = [
            ("separator", types.stringType, true),
            ("prefix", types.stringType, true),
            ("postfix", types.stringType, true),
        ]
        var parameterTypes: [TypeID] = []
        var parameterSymbols: [SymbolID] = []
        var parameterDefaults: [Bool] = []
        for parameter in parameters {
            let parameterName = interner.intern(parameter.name)
            let parameterSymbol = symbols.define(
                kind: .valueParameter,
                name: parameterName,
                fqName: memberFQName + [parameterName],
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
                returnType: types.stringType,
                valueParameterSymbols: parameterSymbols,
                valueParameterHasDefaultValues: parameterDefaults,
                valueParameterIsVararg: Array(repeating: false, count: parameters.count),
                typeParameterSymbols: [listTypeParamSymbol],
                classTypeParameterCount: 1
            ),
            for: memberSymbol
        )
    }

    private func registerListContentEqualsMember(
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner,
        listFQName: [InternedString],
        listInterfaceSymbol: SymbolID,
        listTypeParamSymbol: SymbolID,
        listTypeParamType: TypeID
    ) {
        let memberName = interner.intern("contentEquals")
        let memberFQName = listFQName + [memberName]
        guard symbols.lookup(fqName: memberFQName) == nil else { return }

        let receiverType = types.make(.classType(ClassType(
            classSymbol: listInterfaceSymbol,
            args: [.out(listTypeParamType)],
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
        symbols.setParentSymbol(listInterfaceSymbol, for: memberSymbol)
        symbols.setExternalLinkName("kk_structural_eq", for: memberSymbol)
        symbols.setFunctionSignature(
            FunctionSignature(
                receiverType: receiverType,
                parameterTypes: [types.anyType],
                returnType: types.booleanType,
                typeParameterSymbols: [listTypeParamSymbol],
                classTypeParameterCount: 1
            ),
            for: memberSymbol
        )
    }

    private func registerListToSetMember(
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner,
        listInterfaceSymbol: SymbolID,
        listTypeParamSymbol: SymbolID,
        listTypeParamType: TypeID,
        setInterfaceSymbol: SymbolID
    ) {
        guard let listFQName = symbols.symbol(listInterfaceSymbol)?.fqName else { return }
        let memberName = interner.intern("toSet")
        let memberFQName = listFQName + [memberName]
        guard symbols.lookup(fqName: memberFQName) == nil else { return }
        let receiverType = types.make(.classType(ClassType(
            classSymbol: listInterfaceSymbol,
            args: [.out(listTypeParamType)],
            nullability: .nonNull
        )))
        let setType = types.make(.classType(ClassType(
            classSymbol: setInterfaceSymbol,
            args: [.out(listTypeParamType)],
            nullability: .nonNull
        )))
        let memberSymbol = symbols.define(
            kind: .function,
            name: memberName,
            fqName: memberFQName,
            declSite: nil,
            visibility: .public,
            flags: [.synthetic, .operatorFunction]
        )
        symbols.setParentSymbol(listInterfaceSymbol, for: memberSymbol)
        symbols.setExternalLinkName("kk_list_to_set", for: memberSymbol)
        symbols.setFunctionSignature(
            FunctionSignature(
                receiverType: receiverType,
                parameterTypes: [],
                returnType: setType,
                typeParameterSymbols: [listTypeParamSymbol],
                classTypeParameterCount: 1
            ),
            for: memberSymbol
        )
    }

    /// STDLIB-651: Register `List<T>.toMutableSet()` returning `MutableSet<T>`.
    private func registerListToMutableSetMember(
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner,
        listInterfaceSymbol: SymbolID,
        listTypeParamSymbol: SymbolID,
        listTypeParamType: TypeID,
        mutableSetInterfaceSymbol: SymbolID
    ) {
        guard let listFQName = symbols.symbol(listInterfaceSymbol)?.fqName else { return }
        let memberName = interner.intern("toMutableSet")
        let memberFQName = listFQName + [memberName]
        guard symbols.lookup(fqName: memberFQName) == nil else { return }
        let receiverType = types.make(.classType(ClassType(
            classSymbol: listInterfaceSymbol,
            args: [.out(listTypeParamType)],
            nullability: .nonNull
        )))
        let mutableSetType = types.make(.classType(ClassType(
            classSymbol: mutableSetInterfaceSymbol,
            args: [.out(listTypeParamType)],
            nullability: .nonNull
        )))
        let memberSymbol = symbols.define(
            kind: .function,
            name: memberName,
            fqName: memberFQName,
            declSite: nil,
            visibility: .public,
            flags: [.synthetic, .operatorFunction]
        )
        symbols.setParentSymbol(listInterfaceSymbol, for: memberSymbol)
        symbols.setExternalLinkName("kk_list_to_mutable_set", for: memberSymbol)
        symbols.setFunctionSignature(
            FunctionSignature(
                receiverType: receiverType,
                parameterTypes: [],
                returnType: mutableSetType,
                typeParameterSymbols: [listTypeParamSymbol],
                classTypeParameterCount: 1
            ),
            for: memberSymbol
        )
    }

    /// STDLIB-651: Register `Set<E>.toSet()` returning `Set<E>`.
    private func registerSetToSetMember(
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner,
        setFQName: [InternedString],
        setInterfaceSymbol: SymbolID,
        typeParamSymbol: SymbolID,
        typeParamType: TypeID
    ) {
        let memberName = interner.intern("toSet")
        let memberFQName = setFQName + [memberName]
        guard symbols.lookup(fqName: memberFQName) == nil else { return }
        let receiverType = types.make(.classType(ClassType(
            classSymbol: setInterfaceSymbol,
            args: [.out(typeParamType)],
            nullability: .nonNull
        )))
        let returnType = types.make(.classType(ClassType(
            classSymbol: setInterfaceSymbol,
            args: [.out(typeParamType)],
            nullability: .nonNull
        )))
        let memberSymbol = symbols.define(
            kind: .function,
            name: memberName,
            fqName: memberFQName,
            declSite: nil,
            visibility: .public,
            flags: [.synthetic, .operatorFunction]
        )
        symbols.setParentSymbol(setInterfaceSymbol, for: memberSymbol)
        symbols.setExternalLinkName("kk_set_to_set", for: memberSymbol)
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

    /// STDLIB-651: Register `Set<E>.toMutableSet()` returning `MutableSet<E>`.
    private func registerSetToMutableSetMember(
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner,
        setFQName: [InternedString],
        setInterfaceSymbol: SymbolID,
        typeParamSymbol: SymbolID,
        typeParamType: TypeID,
        mutableSetInterfaceSymbol: SymbolID
    ) {
        let memberName = interner.intern("toMutableSet")
        let memberFQName = setFQName + [memberName]
        guard symbols.lookup(fqName: memberFQName) == nil else { return }
        let receiverType = types.make(.classType(ClassType(
            classSymbol: setInterfaceSymbol,
            args: [.out(typeParamType)],
            nullability: .nonNull
        )))
        let mutableSetType = types.make(.classType(ClassType(
            classSymbol: mutableSetInterfaceSymbol,
            args: [.out(typeParamType)],
            nullability: .nonNull
        )))
        let memberSymbol = symbols.define(
            kind: .function,
            name: memberName,
            fqName: memberFQName,
            declSite: nil,
            visibility: .public,
            flags: [.synthetic, .operatorFunction]
        )
        symbols.setParentSymbol(setInterfaceSymbol, for: memberSymbol)
        symbols.setExternalLinkName("kk_set_to_mutable_set", for: memberSymbol)
        symbols.setFunctionSignature(
            FunctionSignature(
                receiverType: receiverType,
                parameterTypes: [],
                returnType: mutableSetType,
                typeParameterSymbols: [typeParamSymbol],
                classTypeParameterCount: 1
            ),
            for: memberSymbol
        )
    }

    /// STDLIB-510: Register `List<T>.intersect(other)`, `.union(other)`, `.subtract(other)` returning `Set<T>`.
    /// Kotlin stdlib declares the parameter as `Iterable<T>`.
    private func registerListSetOperationMembers(
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner,
        listInterfaceSymbol: SymbolID,
        listTypeParamSymbol: SymbolID,
        listTypeParamType: TypeID,
        setInterfaceSymbol: SymbolID,
        iterableInterfaceSymbol: SymbolID
    ) {
        guard let listFQName = symbols.symbol(listInterfaceSymbol)?.fqName else { return }
        let receiverType = types.make(.classType(ClassType(
            classSymbol: listInterfaceSymbol,
            args: [.out(listTypeParamType)],
            nullability: .nonNull
        )))
        let returnType = types.make(.classType(ClassType(
            classSymbol: setInterfaceSymbol,
            args: [.out(listTypeParamType)],
            nullability: .nonNull
        )))
        let paramType = types.make(.classType(ClassType(
            classSymbol: iterableInterfaceSymbol,
            args: [.out(listTypeParamType)],
            nullability: .nonNull
        )))
        for (memberName, externName) in [
            ("intersect", "kk_list_intersect"),
            ("union", "kk_list_union"),
            ("subtract", "kk_list_subtract"),
        ] {
            let internedName = interner.intern(memberName)
            let memberFQName = listFQName + [internedName]
            guard symbols.lookup(fqName: memberFQName) == nil else { continue }
            let memberSymbol = symbols.define(
                kind: .function,
                name: internedName,
                fqName: memberFQName,
                declSite: nil,
                visibility: .public,
                flags: [.synthetic]
            )
            symbols.setParentSymbol(listInterfaceSymbol, for: memberSymbol)
            symbols.setExternalLinkName(externName, for: memberSymbol)
            symbols.setFunctionSignature(
                FunctionSignature(
                    receiverType: receiverType,
                    parameterTypes: [paramType],
                    returnType: returnType,
                    typeParameterSymbols: [listTypeParamSymbol],
                    classTypeParameterCount: 1
                ),
                for: memberSymbol
            )
        }
    }

    /// STDLIB-510: Register `List<T>.toHashSet()` returning `MutableSet<T>`.
    private func registerListToHashSetMember(
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner,
        listInterfaceSymbol: SymbolID,
        listTypeParamSymbol: SymbolID,
        listTypeParamType: TypeID,
        mutableSetInterfaceSymbol: SymbolID
    ) {
        guard let listFQName = symbols.symbol(listInterfaceSymbol)?.fqName else { return }
        let memberName = interner.intern("toHashSet")
        let memberFQName = listFQName + [memberName]
        guard symbols.lookup(fqName: memberFQName) == nil else { return }
        let receiverType = types.make(.classType(ClassType(
            classSymbol: listInterfaceSymbol,
            args: [.out(listTypeParamType)],
            nullability: .nonNull
        )))
        let mutableSetType = types.make(.classType(ClassType(
            classSymbol: mutableSetInterfaceSymbol,
            args: [.invariant(listTypeParamType)],
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
        symbols.setParentSymbol(listInterfaceSymbol, for: memberSymbol)
        symbols.setExternalLinkName("kk_list_toHashSet", for: memberSymbol)
        symbols.setFunctionSignature(
            FunctionSignature(
                receiverType: receiverType,
                parameterTypes: [],
                returnType: mutableSetType,
                typeParameterSymbols: [listTypeParamSymbol],
                classTypeParameterCount: 1
            ),
            for: memberSymbol
        )
    }

    private func registerListToMapMember(
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner,
        listInterfaceSymbol: SymbolID,
        mapInterfaceSymbol: SymbolID
    ) {
        let pairSymbol = symbols.lookup(
            fqName: [interner.intern("kotlin"), interner.intern("Pair")]
        ) ?? symbols.lookupByShortName(interner.intern("Pair")).first
        guard let pairSymbol,
              let listFQName = symbols.symbol(listInterfaceSymbol)?.fqName
        else {
            return
        }
        let memberName = interner.intern("toMap")
        let memberFQName = listFQName + [memberName]
        guard symbols.lookup(fqName: memberFQName) == nil else { return }

        let keyName = interner.intern("K")
        let valueName = interner.intern("V")
        let keyTypeSymbol = symbols.define(
            kind: .typeParameter,
            name: keyName,
            fqName: memberFQName + [keyName],
            declSite: nil,
            visibility: .private,
            flags: []
        )
        let valueTypeSymbol = symbols.define(
            kind: .typeParameter,
            name: valueName,
            fqName: memberFQName + [valueName],
            declSite: nil,
            visibility: .private,
            flags: []
        )
        let keyType = types.make(.typeParam(TypeParamType(symbol: keyTypeSymbol, nullability: .nonNull)))
        let valueType = types.make(.typeParam(TypeParamType(symbol: valueTypeSymbol, nullability: .nonNull)))
        let pairType = types.make(.classType(ClassType(
            classSymbol: pairSymbol,
            args: [.out(keyType), .out(valueType)],
            nullability: .nonNull
        )))
        let receiverType = types.make(.classType(ClassType(
            classSymbol: listInterfaceSymbol,
            args: [.out(pairType)],
            nullability: .nonNull
        )))
        let mapType = types.make(.classType(ClassType(
            classSymbol: mapInterfaceSymbol,
            args: [.out(keyType), .out(valueType)],
            nullability: .nonNull
        )))

        let memberSymbol = symbols.define(
            kind: .function,
            name: memberName,
            fqName: memberFQName,
            declSite: nil,
            visibility: .public,
            flags: [.synthetic, .operatorFunction]
        )
        symbols.setParentSymbol(listInterfaceSymbol, for: memberSymbol)
        symbols.setParentSymbol(memberSymbol, for: keyTypeSymbol)
        symbols.setParentSymbol(memberSymbol, for: valueTypeSymbol)
        symbols.setExternalLinkName("kk_list_toMap", for: memberSymbol)
        symbols.setFunctionSignature(
            FunctionSignature(
                receiverType: receiverType,
                parameterTypes: [],
                returnType: mapType,
                typeParameterSymbols: [keyTypeSymbol, valueTypeSymbol],
                classTypeParameterCount: 0
            ),
            for: memberSymbol
        )
    }

    /// Register `List<E>.asSequence(): Sequence<E>` member stub (STDLIB-471).
    ///
    /// Note: `Array<E>.asSequence()` does not need a separate Sema stub because
    /// array member calls are resolved through the collection member-call
    /// fallback path (`CallTypeChecker+MemberCallFallbacks`), and the lowering
    /// pass routes to `kk_array_asSequence` via `arrayExprIDs` tracking.
    private func registerListAsSequenceMember(
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner,
        listInterfaceSymbol: SymbolID,
        listTypeParamSymbol: SymbolID,
        listTypeParamType: TypeID
    ) {
        guard let listFQName = symbols.symbol(listInterfaceSymbol)?.fqName else { return }
        let memberName = interner.intern("asSequence")
        let memberFQName = listFQName + [memberName]
        guard symbols.lookup(fqName: memberFQName) == nil else { return }
        let receiverType = types.make(.classType(ClassType(
            classSymbol: listInterfaceSymbol,
            args: [.out(listTypeParamType)],
            nullability: .nonNull
        )))
        // Return type is Sequence<E> — ensure the Sequence interface stub exists.
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
        // Register a type parameter T on Sequence so generic substitution works.
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
        let returnType = types.make(.classType(ClassType(
            classSymbol: sequenceSymbol,
            args: [.out(listTypeParamType)],
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
        symbols.setParentSymbol(listInterfaceSymbol, for: memberSymbol)
        symbols.setExternalLinkName("kk_list_asSequence", for: memberSymbol)
        // typeParameterSymbols lists all type params (class + function-level).
        // classTypeParameterCount: 1 marks the first entry (E) as belonging to
        // List<E>, not to asSequence itself.  This is the standard pattern used
        // by every other List member stub in this file.
        symbols.setFunctionSignature(
            FunctionSignature(
                receiverType: receiverType,
                parameterTypes: [],
                returnType: returnType,
                typeParameterSymbols: [listTypeParamSymbol],
                classTypeParameterCount: 1
            ),
            for: memberSymbol
        )
    }

    private func registerListTransformMembers(
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
        let listReturnType = receiverType

        // Register a synthetic member on List. Short-circuits when a symbol
        // with the same fully-qualified name already exists (first-wins).
        func registerMember(
            name: String,
            parameterTypes: [TypeID],
            externalLinkName: String,
            returnTypeOverride: TypeID? = nil
        ) {
            let memberName = interner.intern(name)
            let memberFQName = listFQName + [memberName]
            guard symbols.lookup(fqName: memberFQName) == nil else { return }
            registerMemberOverload(
                memberName: memberName,
                memberFQName: memberFQName,
                parameterTypes: parameterTypes,
                externalLinkName: externalLinkName,
                returnTypeOverride: returnTypeOverride
            )
        }

        // Register a synthetic member overload on List, checking for
        // duplicate registrations by comparing parameter signatures.
        func registerMemberOverload(
            memberName: InternedString,
            memberFQName: [InternedString],
            parameterTypes: [TypeID],
            externalLinkName: String,
            returnTypeOverride: TypeID? = nil
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
                flags: [.synthetic]
            )
            symbols.setParentSymbol(listInterfaceSymbol, for: memberSymbol)
            symbols.setExternalLinkName(externalLinkName, for: memberSymbol)
            symbols.setFunctionSignature(
                FunctionSignature(
                    receiverType: receiverType,
                    parameterTypes: parameterTypes,
                    returnType: returnTypeOverride ?? listReturnType,
                    typeParameterSymbols: [listTypeParamSymbol],
                    classTypeParameterCount: 1
                ),
                for: memberSymbol
            )
        }

        registerMember(name: "take", parameterTypes: [types.intType], externalLinkName: "kk_list_take")
        registerMember(name: "drop", parameterTypes: [types.intType], externalLinkName: "kk_list_drop")
        registerMember(name: "reversed", parameterTypes: [], externalLinkName: "kk_list_reversed")
        registerMember(name: "asReversed", parameterTypes: [], externalLinkName: "kk_list_as_reversed")
        registerMember(name: "sorted", parameterTypes: [], externalLinkName: "kk_list_sorted")
        registerMember(name: "distinct", parameterTypes: [], externalLinkName: "kk_list_distinct")
        registerMember(name: "shuffled", parameterTypes: [], externalLinkName: "kk_list_shuffled")

        // shuffled(random: Random) overload (STDLIB-531)
        // Requires kotlin.random.Random to be registered first (via
        // registerSyntheticRandomStubs which runs before collection stubs).
        do {
            let shuffledRandomName = interner.intern("shuffled")
            let shuffledRandomFQName = listFQName + [shuffledRandomName]
            let kotlinRandomPkg: [InternedString] = [interner.intern("kotlin"), interner.intern("random")]
            let randomClassName = interner.intern("Random")
            let randomFQName = kotlinRandomPkg + [randomClassName]
            if let randomSymbol = symbols.lookup(fqName: randomFQName) {
                let randomParamType = types.make(.classType(ClassType(
                    classSymbol: randomSymbol,
                    args: [],
                    nullability: .nonNull
                )))
                registerMemberOverload(
                    memberName: shuffledRandomName,
                    memberFQName: shuffledRandomFQName,
                    parameterTypes: [randomParamType],
                    externalLinkName: "kk_list_shuffled_random"
                )
            } else {
                assertionFailure("kotlin.random.Random must be registered before collection stubs")
            }
        }

        registerMember(name: "flatten", parameterTypes: [], externalLinkName: "kk_list_flatten")

        // chunked(size: Int): List<List<E>> and windowed(size: Int, step: Int): List<List<E>>
        // These return List<List<E>>, not List<E>.
        let listOfListReturnType = types.make(.classType(ClassType(
            classSymbol: listInterfaceSymbol,
            args: [.out(listReturnType)],
            nullability: .nonNull
        )))

        registerMemberOverload(
            memberName: interner.intern("chunked"),
            memberFQName: listFQName + [interner.intern("chunked")],
            parameterTypes: [types.intType],
            externalLinkName: "kk_list_chunked",
            returnTypeOverride: listOfListReturnType
        )
        registerMemberOverload(
            memberName: interner.intern("windowed"),
            memberFQName: listFQName + [interner.intern("windowed")],
            parameterTypes: [types.intType],
            externalLinkName: "kk_list_windowed_default",
            returnTypeOverride: listOfListReturnType
        )
        registerMemberOverload(
            memberName: interner.intern("windowed"),
            memberFQName: listFQName + [interner.intern("windowed")],
            parameterTypes: [types.intType, types.intType],
            externalLinkName: "kk_list_windowed",
            returnTypeOverride: listOfListReturnType
        )
        registerMemberOverload(
            memberName: interner.intern("windowed"),
            memberFQName: listFQName + [interner.intern("windowed")],
            parameterTypes: [types.intType, types.intType, types.booleanType],
            externalLinkName: "kk_list_windowed_partial",
            returnTypeOverride: listOfListReturnType
        )
        registerMember(name: "sortedDescending", parameterTypes: [], externalLinkName: "kk_list_sortedDescending")
        registerMember(name: "subList", parameterTypes: [types.intType, types.intType], externalLinkName: "kk_list_subList")

        // chunked(size, transform) — HOF overload (STDLIB-548)
        // Kotlin signature: fun <T, R> Iterable<T>.chunked(size: Int, transform: (List<T>) -> R): List<R>
        // The transform receives a List<T> chunk and returns R. Since R is erased at the
        // runtime ABI level, we model the return type as List<Any> (not List<T>) to avoid
        // mis-typing calls where the transform changes element types.
        let chunkedTransformName = interner.intern("chunked")
        let chunkedTransformFQName = listFQName + [chunkedTransformName]
        // Only register if there isn't already a 2-param overload for "chunked".
        // The 1-arg overload registered above shares the same fqName; check
        // existing overloads by parameter count to avoid duplicate 2-param symbols.
        let existingChunkedOverloads = symbols.lookupAll(fqName: chunkedTransformFQName)
        let hasTwoParamChunked = existingChunkedOverloads.contains { symID in
            guard let sig = symbols.functionSignature(for: symID) else { return false }
            return sig.parameterTypes.count == 2
        }
        if !hasTwoParamChunked {
            // Use invariant List<T> (not List<out T>) for the transform parameter
            // to avoid variance violations when the lambda is in contravariant position.
            let invariantListType = types.make(.classType(ClassType(
                classSymbol: listInterfaceSymbol,
                args: [.invariant(listTypeParamType)],
                nullability: .nonNull
            )))
            let transformType = types.make(.functionType(FunctionType(
                params: [invariantListType],
                returnType: types.anyType,
                isSuspend: false,
                nullability: .nonNull
            )))
            // Return type is List<Any> since the transform can change element types (R != T).
            let listOfAnyReturnType = types.make(.classType(ClassType(
                classSymbol: listInterfaceSymbol,
                args: [.out(types.anyType)],
                nullability: .nonNull
            )))
            let memberSymbol = symbols.define(
                kind: .function,
                name: chunkedTransformName,
                fqName: chunkedTransformFQName,
                declSite: nil,
                visibility: .public,
                flags: [.synthetic, .inlineFunction]
            )
            symbols.setParentSymbol(listInterfaceSymbol, for: memberSymbol)
            symbols.setExternalLinkName("kk_list_chunked_transform", for: memberSymbol)
            symbols.setFunctionSignature(
                FunctionSignature(
                    receiverType: receiverType,
                    parameterTypes: [types.intType, transformType],
                    returnType: listOfAnyReturnType,
                    typeParameterSymbols: [listTypeParamSymbol],
                    classTypeParameterCount: 1
                ),
                for: memberSymbol
            )
        }

        // distinctBy (HOF, selector lambda)
        // Kotlin's `distinctBy` is declared as an extension on Iterable<T>:
        //   fun <T, K> Iterable<T>.distinctBy(selector: (T) -> K): List<T>
        // The compiler models this as a synthetic member on List (not Iterable) because
        // the stub system registers members on concrete collection interfaces.
        // We use `Any?` as the selector return type (erasing K) so that selectors
        // returning nullable keys (e.g., `{ it.name }` where `name` is `String?`)
        // are accepted without a type error.  The runtime compares keys by
        // handle/unboxed-value identity, so nullable vs non-null makes no behavioural
        // difference at the ABI level.
        // NOTE: The selector type `(T) -> Any?` must stay in sync with the expected
        // type in CallTypeChecker+MemberCallInference.swift (case "distinctBy").
        let distinctByName = interner.intern("distinctBy")
        let distinctByFQName = listFQName + [distinctByName]
        if symbols.lookup(fqName: distinctByFQName) == nil {
            let selectorType = types.make(.functionType(FunctionType(
                params: [listTypeParamType],
                returnType: types.nullableAnyType,
                isSuspend: false,
                nullability: .nonNull
            )))
            let memberSymbol = symbols.define(
                kind: .function,
                name: distinctByName,
                fqName: distinctByFQName,
                declSite: nil,
                visibility: .public,
                flags: [.synthetic, .inlineFunction]
            )
            symbols.setParentSymbol(listInterfaceSymbol, for: memberSymbol)
            symbols.setExternalLinkName("kk_list_distinctBy", for: memberSymbol)
            symbols.setFunctionSignature(
                FunctionSignature(
                    receiverType: receiverType,
                    parameterTypes: [selectorType],
                    returnType: listReturnType,
                    typeParameterSymbols: [listTypeParamSymbol],
                    classTypeParameterCount: 1
                ),
                for: memberSymbol
            )
        }
    }

    private func registerListAggregateMembers(
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
            externalLinkName: String
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

        func registerComparableMember(name: String, externalLinkName: String) {
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
                    returnType: nullableElementType,
                    typeParameterSymbols: [listTypeParamSymbol],
                    typeParameterUpperBoundsList: [comparableElementBounds],
                    classTypeParameterCount: 1
                ),
                for: memberSymbol
            )
        }

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
                name: "maxOfOrNull",
                externalLinkName: "kk_list_maxOfOrNull",
                returnTypeBuilder: { selectorResultType in types.makeNullable(selectorResultType) }
            )
            registerByOrNull(
                name: "minOfOrNull",
                externalLinkName: "kk_list_minOfOrNull",
                returnTypeBuilder: { selectorResultType in types.makeNullable(selectorResultType) }
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
        }
        // firstOrNull / lastOrNull no-predicate (STDLIB-210)
        registerSimpleMember(name: "firstOrNull", returnType: nullableElementType, externalLinkName: "kk_list_firstOrNull")
        registerSimpleMember(name: "lastOrNull", returnType: nullableElementType, externalLinkName: "kk_list_lastOrNull")
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
        for (funcName, linkName) in [
            ("takeWhile", "kk_list_takeWhile"),
            ("dropWhile", "kk_list_dropWhile"),
            ("takeLastWhile", "kk_list_takeLastWhile"),
            ("dropLastWhile", "kk_list_dropLastWhile"),
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

        let zipWithNextTransformFQName = zipWithNextFQName + [interner.intern("transform")]
        if symbols.lookup(fqName: zipWithNextTransformFQName) == nil {
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

    private func registerListConversionMembers(
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner,
        kotlinCollectionsPkg: [InternedString],
        listInterfaceSymbol: SymbolID,
        mapInterfaceSymbol: SymbolID,
        collectionInterfaceSymbol: SymbolID
    ) {
        guard let listTypeParamSymbol = symbols.lookup(
            fqName: kotlinCollectionsPkg + [interner.intern("List"), interner.intern("E")]
        ),
            let mutableListSymbol = symbols.lookup(
                fqName: kotlinCollectionsPkg + [interner.intern("MutableList")]
            ),
            let setInterfaceSymbol = symbols.lookup(
                fqName: kotlinCollectionsPkg + [interner.intern("Set")]
            ),
            let mutableSetInterfaceSymbol = symbols.lookup(
                fqName: kotlinCollectionsPkg + [interner.intern("MutableSet")]
            )
        else {
            return
        }
        let listTypeParamType = types.make(.typeParam(TypeParamType(
            symbol: listTypeParamSymbol, nullability: .nonNull
        )))
        registerListToMutableListMember(
            symbols: symbols, types: types, interner: interner,
            listInterfaceSymbol: listInterfaceSymbol,
            listTypeParamSymbol: listTypeParamSymbol,
            listTypeParamType: listTypeParamType,
            mutableListSymbol: mutableListSymbol
        )
        registerListToSetMember(
            symbols: symbols, types: types, interner: interner,
            listInterfaceSymbol: listInterfaceSymbol,
            listTypeParamSymbol: listTypeParamSymbol,
            listTypeParamType: listTypeParamType,
            setInterfaceSymbol: setInterfaceSymbol
        )
        registerListToMapMember(
            symbols: symbols, types: types, interner: interner,
            listInterfaceSymbol: listInterfaceSymbol,
            mapInterfaceSymbol: mapInterfaceSymbol
        )
        let iterableSymbolForOps = symbols.lookup(
            fqName: kotlinCollectionsPkg + [interner.intern("Iterable")]
        ) ?? collectionInterfaceSymbol
        registerListSetOperationMembers(
            symbols: symbols, types: types, interner: interner,
            listInterfaceSymbol: listInterfaceSymbol,
            listTypeParamSymbol: listTypeParamSymbol,
            listTypeParamType: listTypeParamType,
            setInterfaceSymbol: setInterfaceSymbol,
            iterableInterfaceSymbol: iterableSymbolForOps
        )
        registerListToHashSetMember(
            symbols: symbols, types: types, interner: interner,
            listInterfaceSymbol: listInterfaceSymbol,
            listTypeParamSymbol: listTypeParamSymbol,
            listTypeParamType: listTypeParamType,
            mutableSetInterfaceSymbol: mutableSetInterfaceSymbol
        )
        // STDLIB-651: List.toMutableSet() → kk_list_to_mutable_set
        registerListToMutableSetMember(
            symbols: symbols, types: types, interner: interner,
            listInterfaceSymbol: listInterfaceSymbol,
            listTypeParamSymbol: listTypeParamSymbol,
            listTypeParamType: listTypeParamType,
            mutableSetInterfaceSymbol: mutableSetInterfaceSymbol
        )
        registerListAsSequenceMember(
            symbols: symbols, types: types, interner: interner,
            listInterfaceSymbol: listInterfaceSymbol,
            listTypeParamSymbol: listTypeParamSymbol,
            listTypeParamType: listTypeParamType
        )
    }

    /// Register `kotlin.collections.MutableList<E>` interface stub with `operator fun set(index: Int, element: E): E`.
    private func registerSyntheticMutableListStub(
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner,
        kotlinCollectionsPkg: [InternedString],
        listInterfaceSymbol: SymbolID,
        collectionInterfaceSymbol: SymbolID
    ) {
        let listTypeParamName = interner.intern("E")
        let mutableListName = interner.intern("MutableList")
        let mutableListFQName = kotlinCollectionsPkg + [mutableListName]
        let mutableListInterfaceSymbol: SymbolID = if let existing = symbols.lookup(fqName: mutableListFQName) {
            existing
        } else {
            symbols.define(
                kind: .interface,
                name: mutableListName,
                fqName: mutableListFQName,
                declSite: nil,
                visibility: .public,
                flags: [.synthetic]
            )
        }
        // MutableList extends List
        symbols.setDirectSupertypes([listInterfaceSymbol], for: mutableListInterfaceSymbol)
        types.setNominalDirectSupertypes([listInterfaceSymbol], for: mutableListInterfaceSymbol)

        // Define type parameter E for MutableList<E>
        let mlTypeParamFQName = mutableListFQName + [listTypeParamName]
        let mlTypeParamSymbol = symbols.define(
            kind: .typeParameter,
            name: listTypeParamName,
            fqName: mlTypeParamFQName,
            declSite: nil,
            visibility: .private,
            flags: []
        )
        let mlTypeParamType = types.make(.typeParam(TypeParamType(
            symbol: mlTypeParamSymbol, nullability: .nonNull
        )))
        types.setNominalTypeParameterSymbols([mlTypeParamSymbol], for: mutableListInterfaceSymbol)
        types.setNominalTypeParameterVariances([.invariant], for: mutableListInterfaceSymbol)
        symbols.setSupertypeTypeArgs([.out(mlTypeParamType)], for: mutableListInterfaceSymbol, supertype: listInterfaceSymbol)
        types.setNominalSupertypeTypeArgs([.out(mlTypeParamType)], for: mutableListInterfaceSymbol, supertype: listInterfaceSymbol)

        registerMutableListSetOperator(
            symbols: symbols, types: types, interner: interner,
            mutableListFQName: mutableListFQName,
            mutableListInterfaceSymbol: mutableListInterfaceSymbol,
            mlTypeParamSymbol: mlTypeParamSymbol,
            mlTypeParamType: mlTypeParamType
        )
        registerMutableListAddMember(
            symbols: symbols, types: types, interner: interner,
            mutableListFQName: mutableListFQName,
            mutableListInterfaceSymbol: mutableListInterfaceSymbol,
            mlTypeParamSymbol: mlTypeParamSymbol,
            mlTypeParamType: mlTypeParamType
        )
        registerMutableListAddAtMember(
            symbols: symbols, types: types, interner: interner,
            mutableListFQName: mutableListFQName,
            mutableListInterfaceSymbol: mutableListInterfaceSymbol,
            mlTypeParamSymbol: mlTypeParamSymbol,
            mlTypeParamType: mlTypeParamType
        )
        registerMutableListRemoveAtMember(
            symbols: symbols, types: types, interner: interner,
            mutableListFQName: mutableListFQName,
            mutableListInterfaceSymbol: mutableListInterfaceSymbol,
            mlTypeParamSymbol: mlTypeParamSymbol,
            mlTypeParamType: mlTypeParamType
        )
        registerMutableListClearMember(
            symbols: symbols, types: types, interner: interner,
            mutableListFQName: mutableListFQName,
            mutableListInterfaceSymbol: mutableListInterfaceSymbol,
            mlTypeParamSymbol: mlTypeParamSymbol,
            mlTypeParamType: mlTypeParamType
        )
        registerMutableListShuffleMember(
            symbols: symbols, types: types, interner: interner,
            mutableListFQName: mutableListFQName,
            mutableListInterfaceSymbol: mutableListInterfaceSymbol,
            mlTypeParamSymbol: mlTypeParamSymbol,
            mlTypeParamType: mlTypeParamType
        )
        registerMutableListReverseMember(
            symbols: symbols, types: types, interner: interner,
            mutableListFQName: mutableListFQName,
            mutableListInterfaceSymbol: mutableListInterfaceSymbol,
            mlTypeParamSymbol: mlTypeParamSymbol,
            mlTypeParamType: mlTypeParamType
        )
        registerMutableListSortMember(
            symbols: symbols, types: types, interner: interner,
            mutableListFQName: mutableListFQName,
            mutableListInterfaceSymbol: mutableListInterfaceSymbol,
            mlTypeParamSymbol: mlTypeParamSymbol,
            mlTypeParamType: mlTypeParamType
        )
        registerMutableListSortByMember(
            symbols: symbols, types: types, interner: interner,
            mutableListFQName: mutableListFQName,
            mutableListInterfaceSymbol: mutableListInterfaceSymbol,
            mlTypeParamSymbol: mlTypeParamSymbol,
            mlTypeParamType: mlTypeParamType
        )
        registerMutableListSortByDescendingMember(
            symbols: symbols, types: types, interner: interner,
            mutableListFQName: mutableListFQName,
            mutableListInterfaceSymbol: mutableListInterfaceSymbol,
            mlTypeParamSymbol: mlTypeParamSymbol,
            mlTypeParamType: mlTypeParamType
        )
        registerMutableListAddAllMember(
            symbols: symbols, types: types, interner: interner,
            mutableListFQName: mutableListFQName,
            mutableListInterfaceSymbol: mutableListInterfaceSymbol,
            collectionInterfaceSymbol: collectionInterfaceSymbol,
            mlTypeParamSymbol: mlTypeParamSymbol,
            mlTypeParamType: mlTypeParamType
        )
        registerMutableListRemoveAllMember(
            symbols: symbols, types: types, interner: interner,
            mutableListFQName: mutableListFQName,
            mutableListInterfaceSymbol: mutableListInterfaceSymbol,
            collectionInterfaceSymbol: collectionInterfaceSymbol,
            mlTypeParamSymbol: mlTypeParamSymbol,
            mlTypeParamType: mlTypeParamType
        )
        registerMutableListRetainAllMember(
            symbols: symbols, types: types, interner: interner,
            mutableListFQName: mutableListFQName,
            mutableListInterfaceSymbol: mutableListInterfaceSymbol,
            collectionInterfaceSymbol: collectionInterfaceSymbol,
            mlTypeParamSymbol: mlTypeParamSymbol,
            mlTypeParamType: mlTypeParamType
        )
    }

    /// Register `operator fun set(index: Int, element: E): E` on MutableList.
    private func registerMutableListSetOperator(
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner,
        mutableListFQName: [InternedString],
        mutableListInterfaceSymbol: SymbolID,
        mlTypeParamSymbol: SymbolID,
        mlTypeParamType: TypeID
    ) {
        let mlSetName = interner.intern("set")
        let mlSetFQName = mutableListFQName + [mlSetName]
        guard symbols.lookup(fqName: mlSetFQName) == nil else { return }
        let mlReceiverType = types.make(.classType(ClassType(
            classSymbol: mutableListInterfaceSymbol,
            args: [.invariant(mlTypeParamType)],
            nullability: .nonNull
        )))
        let mlSetSymbol = symbols.define(
            kind: .function,
            name: mlSetName,
            fqName: mlSetFQName,
            declSite: nil,
            visibility: .public,
            flags: [.synthetic, .operatorFunction]
        )
        symbols.setParentSymbol(mutableListInterfaceSymbol, for: mlSetSymbol)
        symbols.setExternalLinkName("kk_mutable_list_set", for: mlSetSymbol)
        symbols.setFunctionSignature(
            FunctionSignature(
                receiverType: mlReceiverType,
                parameterTypes: [types.intType, mlTypeParamType],
                returnType: mlTypeParamType,
                typeParameterSymbols: [mlTypeParamSymbol],
                classTypeParameterCount: 1
            ),
            for: mlSetSymbol
        )
    }

    private func registerMutableListAddMember(
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner,
        mutableListFQName: [InternedString],
        mutableListInterfaceSymbol: SymbolID,
        mlTypeParamSymbol: SymbolID,
        mlTypeParamType: TypeID
    ) {
        let memberName = interner.intern("add")
        let memberFQName = mutableListFQName + [memberName]
        guard symbols.lookup(fqName: memberFQName) == nil else { return }
        let receiverType = types.make(.classType(ClassType(
            classSymbol: mutableListInterfaceSymbol,
            args: [.invariant(mlTypeParamType)],
            nullability: .nonNull
        )))
        let memberSymbol = symbols.define(
            kind: .function,
            name: memberName,
            fqName: memberFQName,
            declSite: nil,
            visibility: .public,
            flags: [.synthetic, .operatorFunction]
        )
        symbols.setParentSymbol(mutableListInterfaceSymbol, for: memberSymbol)
        symbols.setExternalLinkName("kk_mutable_list_add", for: memberSymbol)
        symbols.setFunctionSignature(
            FunctionSignature(
                receiverType: receiverType,
                parameterTypes: [mlTypeParamType],
                returnType: types.booleanType,
                typeParameterSymbols: [mlTypeParamSymbol],
                classTypeParameterCount: 1
            ),
            for: memberSymbol
        )
    }

    /// Register `fun add(index: Int, element: E): Unit` on MutableList (insert at index).
    private func registerMutableListAddAtMember(
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner,
        mutableListFQName: [InternedString],
        mutableListInterfaceSymbol: SymbolID,
        mlTypeParamSymbol: SymbolID,
        mlTypeParamType: TypeID
    ) {
        let memberName = interner.intern("add")
        let memberFQName = mutableListFQName + [memberName]
        guard symbols.lookupAll(fqName: memberFQName).first(where: { symbolID in
            guard let existingSignature = symbols.functionSignature(for: symbolID) else {
                return false
            }
            return existingSignature.parameterTypes == [types.intType, mlTypeParamType] &&
                existingSignature.returnType == types.unitType
        }) == nil else {
            return
        }

        let receiverType = types.make(.classType(ClassType(
            classSymbol: mutableListInterfaceSymbol,
            args: [.invariant(mlTypeParamType)],
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
        symbols.setParentSymbol(mutableListInterfaceSymbol, for: memberSymbol)
        symbols.setExternalLinkName("kk_mutable_list_add_at", for: memberSymbol)
        symbols.setFunctionSignature(
            FunctionSignature(
                receiverType: receiverType,
                parameterTypes: [types.intType, mlTypeParamType],
                returnType: types.unitType,
                typeParameterSymbols: [mlTypeParamSymbol],
                classTypeParameterCount: 1
            ),
            for: memberSymbol
        )
    }

    private func registerMutableListRemoveAtMember(
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner,
        mutableListFQName: [InternedString],
        mutableListInterfaceSymbol: SymbolID,
        mlTypeParamSymbol: SymbolID,
        mlTypeParamType: TypeID
    ) {
        let memberName = interner.intern("removeAt")
        let memberFQName = mutableListFQName + [memberName]
        guard symbols.lookup(fqName: memberFQName) == nil else { return }
        let receiverType = types.make(.classType(ClassType(
            classSymbol: mutableListInterfaceSymbol,
            args: [.invariant(mlTypeParamType)],
            nullability: .nonNull
        )))
        let memberSymbol = symbols.define(
            kind: .function,
            name: memberName,
            fqName: memberFQName,
            declSite: nil,
            visibility: .public,
            flags: [.synthetic, .operatorFunction]
        )
        symbols.setParentSymbol(mutableListInterfaceSymbol, for: memberSymbol)
        symbols.setExternalLinkName("kk_mutable_list_removeAt", for: memberSymbol)
        symbols.setFunctionSignature(
            FunctionSignature(
                receiverType: receiverType,
                parameterTypes: [types.intType],
                returnType: mlTypeParamType,
                typeParameterSymbols: [mlTypeParamSymbol],
                classTypeParameterCount: 1
            ),
            for: memberSymbol
        )
    }

    private func registerMutableListClearMember(
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner,
        mutableListFQName: [InternedString],
        mutableListInterfaceSymbol: SymbolID,
        mlTypeParamSymbol: SymbolID,
        mlTypeParamType: TypeID
    ) {
        let memberName = interner.intern("clear")
        let memberFQName = mutableListFQName + [memberName]
        guard symbols.lookup(fqName: memberFQName) == nil else { return }
        let receiverType = types.make(.classType(ClassType(
            classSymbol: mutableListInterfaceSymbol,
            args: [.invariant(mlTypeParamType)],
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
        symbols.setParentSymbol(mutableListInterfaceSymbol, for: memberSymbol)
        symbols.setExternalLinkName("kk_mutable_list_clear", for: memberSymbol)
        symbols.setFunctionSignature(
            FunctionSignature(
                receiverType: receiverType,
                parameterTypes: [],
                returnType: types.unitType,
                typeParameterSymbols: [mlTypeParamSymbol],
                classTypeParameterCount: 1
            ),
            for: memberSymbol
        )
    }

    private func registerMutableListShuffleMember(
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner,
        mutableListFQName: [InternedString],
        mutableListInterfaceSymbol: SymbolID,
        mlTypeParamSymbol: SymbolID,
        mlTypeParamType: TypeID
    ) {
        let memberName = interner.intern("shuffle")
        let memberFQName = mutableListFQName + [memberName]
        guard symbols.lookup(fqName: memberFQName) == nil else { return }
        let receiverType = types.make(.classType(ClassType(
            classSymbol: mutableListInterfaceSymbol,
            args: [.invariant(mlTypeParamType)],
            nullability: .nonNull
        )))
        let memberSymbol = symbols.define(
            kind: .function,
            name: memberName,
            fqName: memberFQName,
            declSite: nil,
            visibility: .public,
            flags: [.synthetic, .operatorFunction]
        )
        symbols.setParentSymbol(mutableListInterfaceSymbol, for: memberSymbol)
        symbols.setExternalLinkName("kk_mutable_list_shuffle", for: memberSymbol)
        symbols.setFunctionSignature(
            FunctionSignature(
                receiverType: receiverType,
                parameterTypes: [],
                returnType: types.unitType,
                typeParameterSymbols: [mlTypeParamSymbol],
                classTypeParameterCount: 1
            ),
            for: memberSymbol
        )
    }

    private func registerMutableListReverseMember(
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner,
        mutableListFQName: [InternedString],
        mutableListInterfaceSymbol: SymbolID,
        mlTypeParamSymbol: SymbolID,
        mlTypeParamType: TypeID
    ) {
        let memberName = interner.intern("reverse")
        let memberFQName = mutableListFQName + [memberName]
        guard symbols.lookup(fqName: memberFQName) == nil else { return }
        let receiverType = types.make(.classType(ClassType(
            classSymbol: mutableListInterfaceSymbol,
            args: [.invariant(mlTypeParamType)],
            nullability: .nonNull
        )))
        let memberSymbol = symbols.define(
            kind: .function,
            name: memberName,
            fqName: memberFQName,
            declSite: nil,
            visibility: .public,
            flags: [.synthetic, .operatorFunction]
        )
        symbols.setParentSymbol(mutableListInterfaceSymbol, for: memberSymbol)
        symbols.setExternalLinkName("kk_mutable_list_reverse", for: memberSymbol)
        symbols.setFunctionSignature(
            FunctionSignature(
                receiverType: receiverType,
                parameterTypes: [],
                returnType: types.unitType,
                typeParameterSymbols: [mlTypeParamSymbol],
                classTypeParameterCount: 1
            ),
            for: memberSymbol
        )
    }

    private func registerMutableListRetainAllMember(
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner,
        mutableListFQName: [InternedString],
        mutableListInterfaceSymbol: SymbolID,
        collectionInterfaceSymbol: SymbolID,
        mlTypeParamSymbol: SymbolID,
        mlTypeParamType: TypeID
    ) {
        let memberName = interner.intern("retainAll")
        let memberFQName = mutableListFQName + [memberName]
        guard symbols.lookup(fqName: memberFQName) == nil else { return }
        let receiverType = types.make(.classType(ClassType(
            classSymbol: mutableListInterfaceSymbol,
            args: [.invariant(mlTypeParamType)],
            nullability: .nonNull
        )))
        let paramType = types.make(.classType(ClassType(
            classSymbol: collectionInterfaceSymbol,
            args: [.out(mlTypeParamType)],
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
        symbols.setParentSymbol(mutableListInterfaceSymbol, for: memberSymbol)
        symbols.setExternalLinkName("kk_mutable_list_retainAll", for: memberSymbol)
        symbols.setFunctionSignature(
            FunctionSignature(
                receiverType: receiverType,
                parameterTypes: [paramType],
                returnType: types.booleanType,
                typeParameterSymbols: [mlTypeParamSymbol],
                classTypeParameterCount: 1
            ),
            for: memberSymbol
        )
    }

    private func registerMutableListSortMember(
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner,
        mutableListFQName: [InternedString],
        mutableListInterfaceSymbol: SymbolID,
        mlTypeParamSymbol: SymbolID,
        mlTypeParamType: TypeID
    ) {
        let memberName = interner.intern("sort")
        let memberFQName = mutableListFQName + [memberName]
        guard symbols.lookup(fqName: memberFQName) == nil else { return }
        let receiverType = types.make(.classType(ClassType(
            classSymbol: mutableListInterfaceSymbol,
            args: [.invariant(mlTypeParamType)],
            nullability: .nonNull
        )))
        let memberSymbol = symbols.define(
            kind: .function,
            name: memberName,
            fqName: memberFQName,
            declSite: nil,
            visibility: .public,
            flags: [.synthetic, .operatorFunction]
        )
        symbols.setParentSymbol(mutableListInterfaceSymbol, for: memberSymbol)
        symbols.setExternalLinkName("kk_mutable_list_sort", for: memberSymbol)
        symbols.setFunctionSignature(
            FunctionSignature(
                receiverType: receiverType,
                parameterTypes: [],
                returnType: types.unitType,
                typeParameterSymbols: [mlTypeParamSymbol],
                classTypeParameterCount: 1
            ),
            for: memberSymbol
        )
    }

    private func registerMutableListSortByMember(
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner,
        mutableListFQName: [InternedString],
        mutableListInterfaceSymbol: SymbolID,
        mlTypeParamSymbol: SymbolID,
        mlTypeParamType: TypeID
    ) {
        let memberName = interner.intern("sortBy")
        let memberFQName = mutableListFQName + [memberName]
        guard symbols.lookup(fqName: memberFQName) == nil else { return }
        let receiverType = types.make(.classType(ClassType(
            classSymbol: mutableListInterfaceSymbol,
            args: [.invariant(mlTypeParamType)],
            nullability: .nonNull
        )))
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
            selectorReturnType = types.anyType
            extraTypeParamSymbols = []
            extraUpperBoundsList = []
        }
        let selectorType = types.make(.functionType(FunctionType(
            params: [mlTypeParamType],
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
        symbols.setParentSymbol(mutableListInterfaceSymbol, for: memberSymbol)
        symbols.setExternalLinkName("kk_mutable_list_sortBy", for: memberSymbol)
        symbols.setFunctionSignature(
            FunctionSignature(
                receiverType: receiverType,
                parameterTypes: [selectorType],
                returnType: types.unitType,
                typeParameterSymbols: [mlTypeParamSymbol] + extraTypeParamSymbols,
                typeParameterUpperBoundsList: [[]] + extraUpperBoundsList,
                classTypeParameterCount: 1
            ),
            for: memberSymbol
        )
    }

    private func registerMutableListSortByDescendingMember(
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner,
        mutableListFQName: [InternedString],
        mutableListInterfaceSymbol: SymbolID,
        mlTypeParamSymbol: SymbolID,
        mlTypeParamType: TypeID
    ) {
        let memberName = interner.intern("sortByDescending")
        let memberFQName = mutableListFQName + [memberName]
        guard symbols.lookup(fqName: memberFQName) == nil else { return }
        let receiverType = types.make(.classType(ClassType(
            classSymbol: mutableListInterfaceSymbol,
            args: [.invariant(mlTypeParamType)],
            nullability: .nonNull
        )))
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
            selectorReturnType = types.anyType
            extraTypeParamSymbols = []
            extraUpperBoundsList = []
        }
        let selectorType = types.make(.functionType(FunctionType(
            params: [mlTypeParamType],
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
        symbols.setParentSymbol(mutableListInterfaceSymbol, for: memberSymbol)
        symbols.setExternalLinkName("kk_mutable_list_sortByDescending", for: memberSymbol)
        symbols.setFunctionSignature(
            FunctionSignature(
                receiverType: receiverType,
                parameterTypes: [selectorType],
                returnType: types.unitType,
                typeParameterSymbols: [mlTypeParamSymbol] + extraTypeParamSymbols,
                typeParameterUpperBoundsList: [[]] + extraUpperBoundsList,
                classTypeParameterCount: 1
            ),
            for: memberSymbol
        )
    }

    private func registerMutableListAddAllMember(
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner,
        mutableListFQName: [InternedString],
        mutableListInterfaceSymbol: SymbolID,
        collectionInterfaceSymbol: SymbolID,
        mlTypeParamSymbol: SymbolID,
        mlTypeParamType: TypeID
    ) {
        let memberName = interner.intern("addAll")
        let memberFQName = mutableListFQName + [memberName]
        guard symbols.lookup(fqName: memberFQName) == nil else { return }
        let receiverType = types.make(.classType(ClassType(
            classSymbol: mutableListInterfaceSymbol,
            args: [.invariant(mlTypeParamType)],
            nullability: .nonNull
        )))
        let paramType = types.make(.classType(ClassType(
            classSymbol: collectionInterfaceSymbol,
            args: [.out(mlTypeParamType)],
            nullability: .nonNull
        )))
        let memberSymbol = symbols.define(
            kind: .function,
            name: memberName,
            fqName: memberFQName,
            declSite: nil,
            visibility: .public,
            flags: [.synthetic, .operatorFunction]
        )
        symbols.setParentSymbol(mutableListInterfaceSymbol, for: memberSymbol)
        symbols.setExternalLinkName("kk_mutable_list_addAll", for: memberSymbol)
        symbols.setFunctionSignature(
            FunctionSignature(
                receiverType: receiverType,
                parameterTypes: [paramType],
                returnType: types.booleanType,
                typeParameterSymbols: [mlTypeParamSymbol],
                classTypeParameterCount: 1
            ),
            for: memberSymbol
        )
    }

    private func registerMutableListRemoveAllMember(
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner,
        mutableListFQName: [InternedString],
        mutableListInterfaceSymbol: SymbolID,
        collectionInterfaceSymbol: SymbolID,
        mlTypeParamSymbol: SymbolID,
        mlTypeParamType: TypeID
    ) {
        let memberName = interner.intern("removeAll")
        let memberFQName = mutableListFQName + [memberName]
        guard symbols.lookup(fqName: memberFQName) == nil else { return }
        let receiverType = types.make(.classType(ClassType(
            classSymbol: mutableListInterfaceSymbol,
            args: [.invariant(mlTypeParamType)],
            nullability: .nonNull
        )))
        let paramType = types.make(.classType(ClassType(
            classSymbol: collectionInterfaceSymbol,
            args: [.out(mlTypeParamType)],
            nullability: .nonNull
        )))
        let memberSymbol = symbols.define(
            kind: .function,
            name: memberName,
            fqName: memberFQName,
            declSite: nil,
            visibility: .public,
            flags: [.synthetic, .operatorFunction]
        )
        symbols.setParentSymbol(mutableListInterfaceSymbol, for: memberSymbol)
        symbols.setExternalLinkName("kk_mutable_list_removeAll", for: memberSymbol)
        symbols.setFunctionSignature(
            FunctionSignature(
                receiverType: receiverType,
                parameterTypes: [paramType],
                returnType: types.booleanType,
                typeParameterSymbols: [mlTypeParamSymbol],
                classTypeParameterCount: 1
            ),
            for: memberSymbol
        )
    }

    private func registerSyntheticSetStub(
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner,
        kotlinCollectionsPkg: [InternedString],
        collectionInterfaceSymbol: SymbolID
    ) -> SymbolID {
        let setName = interner.intern("Set")
        let setFQName = kotlinCollectionsPkg + [setName]
        let setInterfaceSymbol: SymbolID = if let existing = symbols.lookup(fqName: setFQName) {
            existing
        } else {
            symbols.define(
                kind: .interface,
                name: setName,
                fqName: setFQName,
                declSite: nil,
                visibility: .public,
                flags: [.synthetic]
            )
        }

        let typeParamName = interner.intern("E")
        let typeParamFQName = setFQName + [typeParamName]
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
        types.setNominalTypeParameterSymbols([typeParamSymbol], for: setInterfaceSymbol)
        types.setNominalTypeParameterVariances([.out], for: setInterfaceSymbol)
        symbols.setDirectSupertypes([collectionInterfaceSymbol], for: setInterfaceSymbol)
        symbols.setSupertypeTypeArgs([.out(typeParamType)], for: setInterfaceSymbol, supertype: collectionInterfaceSymbol)
        types.setNominalDirectSupertypes([collectionInterfaceSymbol], for: setInterfaceSymbol)
        types.setNominalSupertypeTypeArgs([.out(typeParamType)], for: setInterfaceSymbol, supertype: collectionInterfaceSymbol)

        registerSetContainsMember(
            symbols: symbols, types: types, interner: interner,
            setFQName: setFQName,
            setInterfaceSymbol: setInterfaceSymbol,
            typeParamSymbol: typeParamSymbol,
            typeParamType: typeParamType
        )
        registerSetIsEmptyMember(
            symbols: symbols, types: types, interner: interner,
            setFQName: setFQName,
            setInterfaceSymbol: setInterfaceSymbol,
            typeParamSymbol: typeParamSymbol,
            typeParamType: typeParamType
        )
        registerSetContainsAllMember(
            symbols: symbols, types: types, interner: interner,
            setFQName: setFQName,
            setInterfaceSymbol: setInterfaceSymbol,
            typeParamSymbol: typeParamSymbol,
            typeParamType: typeParamType,
            collectionInterfaceSymbol: collectionInterfaceSymbol
        )
        for (memberName, externName) in [
            ("intersect", "kk_set_intersect"),
            ("union", "kk_set_union"),
            ("subtract", "kk_set_subtract"),
        ] {
            registerSetBinaryOperationMember(
                symbols: symbols, types: types, interner: interner,
                setFQName: setFQName,
                setInterfaceSymbol: setInterfaceSymbol,
                collectionInterfaceSymbol: collectionInterfaceSymbol,
                typeParamSymbol: typeParamSymbol,
                typeParamType: typeParamType,
                memberName: memberName,
                externName: externName
            )
        }

        // STDLIB-651: Set.toSet() → kk_set_to_set
        registerSetToSetMember(
            symbols: symbols, types: types, interner: interner,
            setFQName: setFQName,
            setInterfaceSymbol: setInterfaceSymbol,
            typeParamSymbol: typeParamSymbol,
            typeParamType: typeParamType
        )

        return setInterfaceSymbol
    }

    private func registerSetContainsMember(
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner,
        setFQName: [InternedString],
        setInterfaceSymbol: SymbolID,
        typeParamSymbol: SymbolID,
        typeParamType: TypeID
    ) {
        let memberName = interner.intern("contains")
        let memberFQName = setFQName + [memberName]
        if let existing = symbols.lookup(fqName: memberFQName) {
            symbols.insertFlags([.synthetic, .operatorFunction], for: existing)
            return
        }
        let receiverType = types.make(.classType(ClassType(
            classSymbol: setInterfaceSymbol,
            args: [.out(typeParamType)],
            nullability: .nonNull
        )))
        let memberSymbol = symbols.define(
            kind: .function,
            name: memberName,
            fqName: memberFQName,
            declSite: nil,
            visibility: .public,
            flags: [.synthetic, .operatorFunction]
        )
        symbols.setParentSymbol(setInterfaceSymbol, for: memberSymbol)
        symbols.setExternalLinkName("kk_set_contains", for: memberSymbol)
        symbols.setFunctionSignature(
            FunctionSignature(
                receiverType: receiverType,
                parameterTypes: [typeParamType],
                returnType: types.booleanType,
                typeParameterSymbols: [typeParamSymbol],
                classTypeParameterCount: 1
            ),
            for: memberSymbol
        )
    }

    private func registerSetIsEmptyMember(
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner,
        setFQName: [InternedString],
        setInterfaceSymbol: SymbolID,
        typeParamSymbol: SymbolID,
        typeParamType: TypeID
    ) {
        let memberName = interner.intern("isEmpty")
        let memberFQName = setFQName + [memberName]
        guard symbols.lookup(fqName: memberFQName) == nil else { return }
        let receiverType = types.make(.classType(ClassType(
            classSymbol: setInterfaceSymbol,
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
        symbols.setParentSymbol(setInterfaceSymbol, for: memberSymbol)
        symbols.setExternalLinkName("kk_set_is_empty", for: memberSymbol)
        symbols.setFunctionSignature(
            FunctionSignature(
                receiverType: receiverType,
                parameterTypes: [],
                returnType: types.booleanType,
                typeParameterSymbols: [typeParamSymbol],
                classTypeParameterCount: 1
            ),
            for: memberSymbol
        )
    }

    private func registerSetContainsAllMember(
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner,
        setFQName: [InternedString],
        setInterfaceSymbol: SymbolID,
        typeParamSymbol: SymbolID,
        typeParamType: TypeID,
        collectionInterfaceSymbol: SymbolID
    ) {
        let memberName = interner.intern("containsAll")
        let memberFQName = setFQName + [memberName]
        guard symbols.lookup(fqName: memberFQName) == nil else { return }
        let receiverType = types.make(.classType(ClassType(
            classSymbol: setInterfaceSymbol,
            args: [.out(typeParamType)],
            nullability: .nonNull
        )))
        let collectionType = types.make(.classType(ClassType(
            classSymbol: collectionInterfaceSymbol,
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
        symbols.setParentSymbol(setInterfaceSymbol, for: memberSymbol)
        symbols.setExternalLinkName("kk_set_containsAll", for: memberSymbol)
        symbols.setFunctionSignature(
            FunctionSignature(
                receiverType: receiverType,
                parameterTypes: [collectionType],
                returnType: types.booleanType,
                typeParameterSymbols: [typeParamSymbol],
                classTypeParameterCount: 1
            ),
            for: memberSymbol
        )
    }

    private func registerSetBinaryOperationMember(
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner,
        setFQName: [InternedString],
        setInterfaceSymbol: SymbolID,
        collectionInterfaceSymbol: SymbolID,
        typeParamSymbol: SymbolID,
        typeParamType: TypeID,
        memberName: String,
        externName: String
    ) {
        let internedMemberName = interner.intern(memberName)
        let memberFQName = setFQName + [internedMemberName]
        guard symbols.lookup(fqName: memberFQName) == nil else { return }
        let setType = types.make(.classType(ClassType(
            classSymbol: setInterfaceSymbol,
            args: [.out(typeParamType)],
            nullability: .nonNull
        )))
        let paramType = types.make(.classType(ClassType(
            classSymbol: collectionInterfaceSymbol,
            args: [.out(typeParamType)],
            nullability: .nonNull
        )))
        let memberSymbol = symbols.define(
            kind: .function,
            name: internedMemberName,
            fqName: memberFQName,
            declSite: nil,
            visibility: .public,
            flags: [.synthetic]
        )
        symbols.setParentSymbol(setInterfaceSymbol, for: memberSymbol)
        symbols.setExternalLinkName(externName, for: memberSymbol)
        symbols.setFunctionSignature(
            FunctionSignature(
                receiverType: setType,
                parameterTypes: [paramType],
                returnType: setType,
                typeParameterSymbols: [typeParamSymbol],
                classTypeParameterCount: 1
            ),
            for: memberSymbol
        )
    }

    private func registerSyntheticMutableSetStub(
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner,
        kotlinCollectionsPkg: [InternedString],
        setInterfaceSymbol: SymbolID,
        collectionInterfaceSymbol: SymbolID
    ) {
        let typeParamName = interner.intern("E")
        let mutableSetName = interner.intern("MutableSet")
        let mutableSetFQName = kotlinCollectionsPkg + [mutableSetName]
        let mutableSetInterfaceSymbol: SymbolID = if let existing = symbols.lookup(fqName: mutableSetFQName) {
            existing
        } else {
            symbols.define(
                kind: .interface,
                name: mutableSetName,
                fqName: mutableSetFQName,
                declSite: nil,
                visibility: .public,
                flags: [.synthetic]
            )
        }
        symbols.setDirectSupertypes([setInterfaceSymbol], for: mutableSetInterfaceSymbol)

        let typeParamFQName = mutableSetFQName + [typeParamName]
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

        registerMutableSetAddMember(
            symbols: symbols, types: types, interner: interner,
            mutableSetFQName: mutableSetFQName,
            mutableSetInterfaceSymbol: mutableSetInterfaceSymbol,
            typeParamSymbol: typeParamSymbol,
            typeParamType: typeParamType
        )
        registerMutableSetRemoveMember(
            symbols: symbols, types: types, interner: interner,
            mutableSetFQName: mutableSetFQName,
            mutableSetInterfaceSymbol: mutableSetInterfaceSymbol,
            typeParamSymbol: typeParamSymbol,
            typeParamType: typeParamType
        )
        registerMutableSetClearMember(
            symbols: symbols, types: types, interner: interner,
            mutableSetFQName: mutableSetFQName,
            mutableSetInterfaceSymbol: mutableSetInterfaceSymbol,
            typeParamSymbol: typeParamSymbol,
            typeParamType: typeParamType
        )
        registerMutableSetAddAllMember(
            symbols: symbols, types: types, interner: interner,
            mutableSetFQName: mutableSetFQName,
            mutableSetInterfaceSymbol: mutableSetInterfaceSymbol,
            collectionInterfaceSymbol: collectionInterfaceSymbol,
            typeParamSymbol: typeParamSymbol,
            typeParamType: typeParamType
        )

        // STDLIB-651: Set.toMutableSet() → kk_set_to_mutable_set
        // Register on Set (not MutableSet) since Set.toMutableSet() returns MutableSet
        if let setFQName = symbols.symbol(setInterfaceSymbol)?.fqName {
            let setTypeParamName = interner.intern("E")
            let setTypeParamFQName = setFQName + [setTypeParamName]
            if let setTypeParamSymbol = symbols.lookup(fqName: setTypeParamFQName) {
                let setTypeParamType = types.make(.typeParam(TypeParamType(
                    symbol: setTypeParamSymbol, nullability: .nonNull
                )))
                registerSetToMutableSetMember(
                    symbols: symbols, types: types, interner: interner,
                    setFQName: setFQName,
                    setInterfaceSymbol: setInterfaceSymbol,
                    typeParamSymbol: setTypeParamSymbol,
                    typeParamType: setTypeParamType,
                    mutableSetInterfaceSymbol: mutableSetInterfaceSymbol
                )
            }
        }
    }

    private func registerMutableSetAddMember(
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner,
        mutableSetFQName: [InternedString],
        mutableSetInterfaceSymbol: SymbolID,
        typeParamSymbol: SymbolID,
        typeParamType: TypeID
    ) {
        let memberName = interner.intern("add")
        let memberFQName = mutableSetFQName + [memberName]
        guard symbols.lookup(fqName: memberFQName) == nil else { return }
        let receiverType = types.make(.classType(ClassType(
            classSymbol: mutableSetInterfaceSymbol,
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
        symbols.setParentSymbol(mutableSetInterfaceSymbol, for: memberSymbol)
        symbols.setExternalLinkName("kk_mutable_set_add", for: memberSymbol)
        symbols.setFunctionSignature(
            FunctionSignature(
                receiverType: receiverType,
                parameterTypes: [typeParamType],
                returnType: types.booleanType,
                typeParameterSymbols: [typeParamSymbol],
                classTypeParameterCount: 1
            ),
            for: memberSymbol
        )
    }

    private func registerMutableSetRemoveMember(
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner,
        mutableSetFQName: [InternedString],
        mutableSetInterfaceSymbol: SymbolID,
        typeParamSymbol: SymbolID,
        typeParamType: TypeID
    ) {
        let memberName = interner.intern("remove")
        let memberFQName = mutableSetFQName + [memberName]
        guard symbols.lookup(fqName: memberFQName) == nil else { return }
        let receiverType = types.make(.classType(ClassType(
            classSymbol: mutableSetInterfaceSymbol,
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
        symbols.setParentSymbol(mutableSetInterfaceSymbol, for: memberSymbol)
        symbols.setExternalLinkName("kk_mutable_set_remove", for: memberSymbol)
        symbols.setFunctionSignature(
            FunctionSignature(
                receiverType: receiverType,
                parameterTypes: [typeParamType],
                returnType: types.booleanType,
                typeParameterSymbols: [typeParamSymbol],
                classTypeParameterCount: 1
            ),
            for: memberSymbol
        )
    }

    private func registerMutableSetClearMember(
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner,
        mutableSetFQName: [InternedString],
        mutableSetInterfaceSymbol: SymbolID,
        typeParamSymbol: SymbolID,
        typeParamType: TypeID
    ) {
        let memberName = interner.intern("clear")
        let memberFQName = mutableSetFQName + [memberName]
        guard symbols.lookup(fqName: memberFQName) == nil else { return }
        let receiverType = types.make(.classType(ClassType(
            classSymbol: mutableSetInterfaceSymbol,
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
        symbols.setParentSymbol(mutableSetInterfaceSymbol, for: memberSymbol)
        symbols.setExternalLinkName("kk_mutable_set_clear", for: memberSymbol)
        symbols.setFunctionSignature(
            FunctionSignature(
                receiverType: receiverType,
                parameterTypes: [],
                returnType: types.unitType,
                typeParameterSymbols: [typeParamSymbol],
                classTypeParameterCount: 1
            ),
            for: memberSymbol
        )
    }

    private func registerMutableSetAddAllMember(
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner,
        mutableSetFQName: [InternedString],
        mutableSetInterfaceSymbol: SymbolID,
        collectionInterfaceSymbol: SymbolID,
        typeParamSymbol: SymbolID,
        typeParamType: TypeID
    ) {
        let memberName = interner.intern("addAll")
        let memberFQName = mutableSetFQName + [memberName]
        guard symbols.lookup(fqName: memberFQName) == nil else { return }
        let receiverType = types.make(.classType(ClassType(
            classSymbol: mutableSetInterfaceSymbol,
            args: [.invariant(typeParamType)],
            nullability: .nonNull
        )))
        let collectionType = types.make(.classType(ClassType(
            classSymbol: collectionInterfaceSymbol,
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
        symbols.setParentSymbol(mutableSetInterfaceSymbol, for: memberSymbol)
        symbols.setExternalLinkName("kk_mutable_set_addAll", for: memberSymbol)
        symbols.setFunctionSignature(
            FunctionSignature(
                receiverType: receiverType,
                parameterTypes: [collectionType],
                returnType: types.booleanType,
                typeParameterSymbols: [typeParamSymbol],
                classTypeParameterCount: 1
            ),
            for: memberSymbol
        )
    }

    private func registerSyntheticMapStub(
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner,
        kotlinCollectionsPkg: [InternedString]
    ) -> (mapSymbol: SymbolID, keyTypeParamSymbol: SymbolID, valueTypeParamSymbol: SymbolID) {
        let mapName = interner.intern("Map")
        let mapFQName = kotlinCollectionsPkg + [mapName]
        let mapSymbol: SymbolID = if let existing = symbols.lookup(fqName: mapFQName) {
            existing
        } else {
            symbols.define(
                kind: .interface,
                name: mapName,
                fqName: mapFQName,
                declSite: nil,
                visibility: .public,
                flags: [.synthetic]
            )
        }

        let keyName = interner.intern("K")
        let valueName = interner.intern("V")
        let keyParamSymbol = symbols.define(
            kind: .typeParameter,
            name: keyName,
            fqName: mapFQName + [keyName],
            declSite: nil,
            visibility: .private,
            flags: []
        )
        let valueParamSymbol = symbols.define(
            kind: .typeParameter,
            name: valueName,
            fqName: mapFQName + [valueName],
            declSite: nil,
            visibility: .private,
            flags: []
        )
        types.setNominalTypeParameterSymbols([keyParamSymbol, valueParamSymbol], for: mapSymbol)
        types.setNominalTypeParameterVariances([.invariant, .out], for: mapSymbol)

        let keyType = types.make(.typeParam(TypeParamType(symbol: keyParamSymbol, nullability: .nonNull)))
        let valueType = types.make(.typeParam(TypeParamType(symbol: valueParamSymbol, nullability: .nonNull)))
        let receiverType = types.make(.classType(ClassType(
            classSymbol: mapSymbol,
            args: [.invariant(keyType), .out(valueType)],
            nullability: .nonNull
        )))

        let getName = interner.intern("get")
        let getFQName = mapFQName + [getName]
        if symbols.lookup(fqName: getFQName) == nil {
            let getSymbol = symbols.define(
                kind: .function,
                name: getName,
                fqName: getFQName,
                declSite: nil,
                visibility: .public,
                flags: [.synthetic, .operatorFunction]
            )
            symbols.setParentSymbol(mapSymbol, for: getSymbol)
            symbols.setExternalLinkName("kk_map_get", for: getSymbol)
            symbols.setFunctionSignature(
                FunctionSignature(
                    receiverType: receiverType,
                    parameterTypes: [keyType],
                    returnType: types.makeNullable(valueType),
                    typeParameterSymbols: [keyParamSymbol, valueParamSymbol],
                    classTypeParameterCount: 2
                ),
                for: getSymbol
            )
        }

        let containsKeyName = interner.intern("containsKey")
        let containsKeyFQName = mapFQName + [containsKeyName]
        if symbols.lookup(fqName: containsKeyFQName) == nil {
            let containsKeySymbol = symbols.define(
                kind: .function,
                name: containsKeyName,
                fqName: containsKeyFQName,
                declSite: nil,
                visibility: .public,
                flags: [.synthetic]
            )
            symbols.setParentSymbol(mapSymbol, for: containsKeySymbol)
            symbols.setExternalLinkName("kk_map_contains_key", for: containsKeySymbol)
            symbols.setFunctionSignature(
                FunctionSignature(
                    receiverType: receiverType,
                    parameterTypes: [keyType],
                    returnType: types.booleanType,
                    typeParameterSymbols: [keyParamSymbol, valueParamSymbol],
                    classTypeParameterCount: 2
                ),
                for: containsKeySymbol
            )
        }

        let containsValueName = interner.intern("containsValue")
        let containsValueFQName = mapFQName + [containsValueName]
        if symbols.lookup(fqName: containsValueFQName) == nil {
            let containsValueSymbol = symbols.define(
                kind: .function,
                name: containsValueName,
                fqName: containsValueFQName,
                declSite: nil,
                visibility: .public,
                flags: [.synthetic]
            )
            symbols.setParentSymbol(mapSymbol, for: containsValueSymbol)
            symbols.setExternalLinkName("kk_map_contains_value", for: containsValueSymbol)
            symbols.setFunctionSignature(
                FunctionSignature(
                    receiverType: receiverType,
                    parameterTypes: [valueType],
                    returnType: types.booleanType,
                    typeParameterSymbols: [keyParamSymbol, valueParamSymbol],
                    classTypeParameterCount: 2
                ),
                for: containsValueSymbol
            )
        }

        return (mapSymbol, keyParamSymbol, valueParamSymbol)
    }

    private func registerMapToMutableMapMember(
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner,
        kotlinCollectionsPkg: [InternedString],
        mapInterfaceSymbol: SymbolID,
        keyTypeParamSymbol: SymbolID,
        valueTypeParamSymbol: SymbolID
    ) {
        let mapFQName = kotlinCollectionsPkg + [interner.intern("Map")]
        let toMutableMapName = interner.intern("toMutableMap")
        let toMutableMapFQName = mapFQName + [toMutableMapName]
        guard symbols.lookup(fqName: toMutableMapFQName) == nil else { return }
        guard let mutableMapSymbol = symbols.lookup(fqName: kotlinCollectionsPkg + [interner.intern("MutableMap")]) else {
            return
        }
        let keyType = types.make(.typeParam(TypeParamType(symbol: keyTypeParamSymbol, nullability: .nonNull)))
        let valueType = types.make(.typeParam(TypeParamType(symbol: valueTypeParamSymbol, nullability: .nonNull)))
        let receiverType = types.make(.classType(ClassType(
            classSymbol: mapInterfaceSymbol,
            args: [.out(keyType), .out(valueType)],
            nullability: .nonNull
        )))
        let memberSymbol = symbols.define(
            kind: .function,
            name: toMutableMapName,
            fqName: toMutableMapFQName,
            declSite: nil,
            visibility: .public,
            flags: [.synthetic]
        )
        symbols.setParentSymbol(mapInterfaceSymbol, for: memberSymbol)
        symbols.setExternalLinkName("kk_map_to_mutable_map", for: memberSymbol)
        symbols.setFunctionSignature(
            FunctionSignature(
                receiverType: receiverType,
                parameterTypes: [],
                returnType: types.make(.classType(ClassType(
                    classSymbol: mutableMapSymbol,
                    args: [.invariant(keyType), .invariant(valueType)],
                    nullability: .nonNull
                ))),
                typeParameterSymbols: [keyTypeParamSymbol, valueTypeParamSymbol],
                classTypeParameterCount: 2
            ),
            for: memberSymbol
        )
    }

    private func registerMapHigherOrderMembers(
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner,
        kotlinCollectionsPkg: [InternedString],
        mapInterfaceSymbol: SymbolID,
        keyTypeParamSymbol: SymbolID,
        valueTypeParamSymbol: SymbolID,
        collectionInterfaceSymbol: SymbolID
    ) {
        let mapFQName = kotlinCollectionsPkg + [interner.intern("Map")]
        let keyType = types.make(.typeParam(TypeParamType(symbol: keyTypeParamSymbol, nullability: .nonNull)))
        let valueType = types.make(.typeParam(TypeParamType(symbol: valueTypeParamSymbol, nullability: .nonNull)))
        let receiverType = types.make(.classType(ClassType(
            classSymbol: mapInterfaceSymbol,
            args: [.out(keyType), .out(valueType)],
            nullability: .nonNull
        )))
        let entryType = registerSyntheticMapEntryStub(
            symbols: symbols,
            types: types,
            interner: interner,
            kotlinCollectionsPkg: kotlinCollectionsPkg,
            mapInterfaceSymbol: mapInterfaceSymbol,
            keyTypeParamSymbol: keyTypeParamSymbol,
            valueTypeParamSymbol: valueTypeParamSymbol
        )
        let pairSymbol = symbols.lookup(fqName: [interner.intern("kotlin"), interner.intern("Pair")])
            ?? symbols.lookupByShortName(interner.intern("Pair")).first
        let pairType = if let pairSymbol {
            types.make(.classType(ClassType(
                classSymbol: pairSymbol,
                args: [.invariant(keyType), .invariant(valueType)],
                nullability: .nonNull
            )))
        } else {
            types.anyType
        }

        let listSymbol = symbols.lookup(fqName: kotlinCollectionsPkg + [interner.intern("List")])
            ?? symbols.lookupByShortName(interner.intern("List")).first
        let setSymbol = symbols.lookup(fqName: kotlinCollectionsPkg + [interner.intern("Set")])
            ?? symbols.lookupByShortName(interner.intern("Set")).first

        func registerMember(
            name: String,
            externalLinkName: String,
            parameterTypes: [TypeID],
            returnType: TypeID,
            typeParameterSymbols: [SymbolID],
            flags: SymbolFlags = [.synthetic]
        ) {
            let memberName = interner.intern(name)
            let memberFQName = mapFQName + [memberName]
            guard symbols.lookup(fqName: memberFQName) == nil else { return }
            let memberSymbol = symbols.define(
                kind: .function,
                name: memberName,
                fqName: memberFQName,
                declSite: nil,
                visibility: .public,
                flags: flags
            )
            symbols.setParentSymbol(mapInterfaceSymbol, for: memberSymbol)
            symbols.setExternalLinkName(externalLinkName, for: memberSymbol)
            symbols.setFunctionSignature(
                FunctionSignature(
                    receiverType: receiverType,
                    parameterTypes: parameterTypes,
                    returnType: returnType,
                    typeParameterSymbols: typeParameterSymbols,
                    classTypeParameterCount: 2
                ),
                for: memberSymbol
            )
        }

        if let setSymbol {
            let keysType = types.make(.classType(ClassType(
                classSymbol: setSymbol,
                args: [.out(keyType)],
                nullability: .nonNull
            )))
            registerMember(
                name: "keys",
                externalLinkName: "kk_map_keys",
                parameterTypes: [],
                returnType: keysType,
                typeParameterSymbols: [keyTypeParamSymbol, valueTypeParamSymbol]
            )

            let entriesType = types.make(.classType(ClassType(
                classSymbol: setSymbol,
                args: [.out(entryType)],
                nullability: .nonNull
            )))
            registerMember(
                name: "entries",
                externalLinkName: "kk_map_entries",
                parameterTypes: [],
                returnType: entriesType,
                typeParameterSymbols: [keyTypeParamSymbol, valueTypeParamSymbol]
            )
        }

        let valuesType = types.make(.classType(ClassType(
            classSymbol: collectionInterfaceSymbol,
            args: [.out(valueType)],
            nullability: .nonNull
        )))
        registerMember(
            name: "values",
            externalLinkName: "kk_map_values",
            parameterTypes: [],
            returnType: valuesType,
            typeParameterSymbols: [keyTypeParamSymbol, valueTypeParamSymbol]
        )

        let forEachLambdaType = types.make(.functionType(FunctionType(
            params: [entryType],
            returnType: types.unitType,
            isSuspend: false,
            nullability: .nonNull
        )))
        registerMember(
            name: "forEach",
            externalLinkName: "kk_map_forEach",
            parameterTypes: [forEachLambdaType],
            returnType: types.unitType,
            typeParameterSymbols: [keyTypeParamSymbol, valueTypeParamSymbol],
            flags: [.synthetic, .inlineFunction]
        )

        if let listSymbol {
            let rName = interner.intern("R")
            let rSymbol = symbols.define(
                kind: .typeParameter,
                name: rName,
                fqName: mapFQName + [interner.intern("map"), rName],
                declSite: nil,
                visibility: .private,
                flags: []
            )
            let rType = types.make(.typeParam(TypeParamType(symbol: rSymbol, nullability: .nullable)))
            let mapLambdaType = types.make(.functionType(FunctionType(
                params: [entryType],
                returnType: rType,
                isSuspend: false,
                nullability: .nonNull
            )))
            let listRType = types.make(.classType(ClassType(
                classSymbol: listSymbol,
                args: [.out(rType)],
                nullability: .nonNull
            )))
            registerMember(
                name: "map",
                externalLinkName: "kk_map_map",
                parameterTypes: [mapLambdaType],
                returnType: listRType,
                typeParameterSymbols: [keyTypeParamSymbol, valueTypeParamSymbol, rSymbol],
                flags: [.synthetic, .inlineFunction]
            )
        }

        let mapValuesName = interner.intern("mapValues")
        let mapValuesFQName = mapFQName + [mapValuesName]
        if symbols.lookup(fqName: mapValuesFQName) == nil {
            let rName = interner.intern("R")
            let rSymbol = symbols.define(
                kind: .typeParameter,
                name: rName,
                fqName: mapValuesFQName + [rName],
                declSite: nil,
                visibility: .private,
                flags: []
            )
            let rType = types.make(.typeParam(TypeParamType(symbol: rSymbol, nullability: .nonNull)))
            let transformType = types.make(.functionType(FunctionType(
                params: [entryType],
                returnType: rType,
                isSuspend: false,
                nullability: .nonNull
            )))
            let mapRType = types.make(.classType(ClassType(
                classSymbol: mapInterfaceSymbol,
                args: [.out(keyType), .out(rType)],
                nullability: .nonNull
            )))
            registerMember(
                name: "mapValues",
                externalLinkName: "kk_map_mapValues",
                parameterTypes: [transformType],
                returnType: mapRType,
                typeParameterSymbols: [keyTypeParamSymbol, valueTypeParamSymbol, rSymbol],
                flags: [.synthetic, .inlineFunction]
            )
        }

        let mapKeysName = interner.intern("mapKeys")
        let mapKeysFQName = mapFQName + [mapKeysName]
        if symbols.lookup(fqName: mapKeysFQName) == nil {
            let rName = interner.intern("R")
            let rSymbol = symbols.define(
                kind: .typeParameter,
                name: rName,
                fqName: mapKeysFQName + [rName],
                declSite: nil,
                visibility: .private,
                flags: []
            )
            let rType = types.make(.typeParam(TypeParamType(symbol: rSymbol, nullability: .nonNull)))
            let transformType = types.make(.functionType(FunctionType(
                params: [entryType],
                returnType: rType,
                isSuspend: false,
                nullability: .nonNull
            )))
            let mapRType = types.make(.classType(ClassType(
                classSymbol: mapInterfaceSymbol,
                args: [.out(rType), .out(valueType)],
                nullability: .nonNull
            )))
            registerMember(
                name: "mapKeys",
                externalLinkName: "kk_map_mapKeys",
                parameterTypes: [transformType],
                returnType: mapRType,
                typeParameterSymbols: [keyTypeParamSymbol, valueTypeParamSymbol, rSymbol],
                flags: [.synthetic, .inlineFunction]
            )
        }

        let filterLambdaType = types.make(.functionType(FunctionType(
            params: [entryType],
            returnType: types.booleanType,
            isSuspend: false,
            nullability: .nonNull
        )))
        registerMember(
            name: "filter",
            externalLinkName: "kk_map_filter",
            parameterTypes: [filterLambdaType],
            returnType: receiverType,
            typeParameterSymbols: [keyTypeParamSymbol, valueTypeParamSymbol],
            flags: [.synthetic, .inlineFunction]
        )

        registerMember(
            name: "count",
            externalLinkName: "kk_map_count",
            parameterTypes: [filterLambdaType],
            returnType: types.intType,
            typeParameterSymbols: [keyTypeParamSymbol, valueTypeParamSymbol],
            flags: [.synthetic, .inlineFunction]
        )
        registerMember(
            name: "any",
            externalLinkName: "kk_map_any",
            parameterTypes: [filterLambdaType],
            returnType: types.booleanType,
            typeParameterSymbols: [keyTypeParamSymbol, valueTypeParamSymbol],
            flags: [.synthetic, .inlineFunction]
        )
        registerMember(
            name: "all",
            externalLinkName: "kk_map_all",
            parameterTypes: [filterLambdaType],
            returnType: types.booleanType,
            typeParameterSymbols: [keyTypeParamSymbol, valueTypeParamSymbol],
            flags: [.synthetic, .inlineFunction]
        )
        registerMember(
            name: "none",
            externalLinkName: "kk_map_none",
            parameterTypes: [filterLambdaType],
            returnType: types.booleanType,
            typeParameterSymbols: [keyTypeParamSymbol, valueTypeParamSymbol],
            flags: [.synthetic, .inlineFunction]
        )

        registerMember(
            name: "getValue",
            externalLinkName: "kk_map_getValue",
            parameterTypes: [keyType],
            returnType: valueType,
            typeParameterSymbols: [keyTypeParamSymbol, valueTypeParamSymbol]
        )

        registerMember(
            name: "getOrDefault",
            externalLinkName: "kk_map_getOrDefault",
            parameterTypes: [keyType, valueType],
            returnType: valueType,
            typeParameterSymbols: [keyTypeParamSymbol, valueTypeParamSymbol]
        )

        registerMember(
            name: "plus",
            externalLinkName: "kk_map_plus",
            parameterTypes: [pairType],
            returnType: receiverType,
            typeParameterSymbols: [keyTypeParamSymbol, valueTypeParamSymbol],
            flags: [.synthetic, .operatorFunction]
        )

        registerMember(
            name: "minus",
            externalLinkName: "kk_map_minus",
            parameterTypes: [keyType],
            returnType: receiverType,
            typeParameterSymbols: [keyTypeParamSymbol, valueTypeParamSymbol],
            flags: [.synthetic, .operatorFunction]
        )

        let getOrElseLambdaType = types.make(.functionType(FunctionType(
            params: [],
            returnType: valueType,
            isSuspend: false,
            nullability: .nonNull
        )))
        registerMember(
            name: "getOrElse",
            externalLinkName: "kk_map_getOrElse",
            parameterTypes: [keyType, getOrElseLambdaType],
            returnType: valueType,
            typeParameterSymbols: [keyTypeParamSymbol, valueTypeParamSymbol],
            flags: [.synthetic, .inlineFunction]
        )

        if let listSymbol {
            let toListType = types.make(.classType(ClassType(
                classSymbol: listSymbol,
                args: [.out(pairType)],
                nullability: .nonNull
            )))
            registerMember(
                name: "toList",
                externalLinkName: "kk_map_toList",
                parameterTypes: [],
                returnType: toListType,
                typeParameterSymbols: [keyTypeParamSymbol, valueTypeParamSymbol]
            )

            let rName = interner.intern("R")
            let flatMapRSymbol = symbols.define(
                kind: .typeParameter,
                name: rName,
                fqName: mapFQName + [interner.intern("flatMap"), rName],
                declSite: nil,
                visibility: .private,
                flags: []
            )
            let flatMapRType = types.make(.typeParam(TypeParamType(symbol: flatMapRSymbol, nullability: .nullable)))
            let flatMapLambdaReturnType = types.make(.classType(ClassType(
                classSymbol: listSymbol,
                args: [.out(flatMapRType)],
                nullability: .nonNull
            )))
            let flatMapLambdaType = types.make(.functionType(FunctionType(
                params: [entryType],
                returnType: flatMapLambdaReturnType,
                isSuspend: false,
                nullability: .nonNull
            )))
            let flatMapReturnType = types.make(.classType(ClassType(
                classSymbol: listSymbol,
                args: [.out(flatMapRType)],
                nullability: .nonNull
            )))
            registerMember(
                name: "flatMap",
                externalLinkName: "kk_map_flatMap",
                parameterTypes: [flatMapLambdaType],
                returnType: flatMapReturnType,
                typeParameterSymbols: [keyTypeParamSymbol, valueTypeParamSymbol, flatMapRSymbol],
                flags: [.synthetic, .inlineFunction]
            )
        }

        // maxByOrNull / minByOrNull with R: Comparable<R> selector
        let nullableEntryType = types.makeNullable(entryType)
        do {
            func registerMapByOrNull(name: String, externalLinkName: String) {
                let memberName = interner.intern(name)
                let memberFQName = mapFQName + [memberName]
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
                    selectorReturnType = types.anyType
                    extraTypeParamSymbols = []
                    extraUpperBoundsList = []
                }
                let selectorType = types.make(.functionType(FunctionType(
                    params: [entryType],
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
                symbols.setParentSymbol(mapInterfaceSymbol, for: memberSymbol)
                symbols.setExternalLinkName(externalLinkName, for: memberSymbol)
                symbols.setFunctionSignature(
                    FunctionSignature(
                        receiverType: receiverType,
                        parameterTypes: [selectorType],
                        returnType: nullableEntryType,
                        typeParameterSymbols: [keyTypeParamSymbol, valueTypeParamSymbol] + extraTypeParamSymbols,
                        typeParameterUpperBoundsList: [[], []] + extraUpperBoundsList,
                        classTypeParameterCount: 2
                    ),
                    for: memberSymbol
                )
            }

            registerMapByOrNull(name: "maxByOrNull", externalLinkName: "kk_map_maxByOrNull")
            registerMapByOrNull(name: "minByOrNull", externalLinkName: "kk_map_minByOrNull")
        }
    }

    private func registerSyntheticMapEntryStub(
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner,
        kotlinCollectionsPkg: [InternedString],
        mapInterfaceSymbol: SymbolID,
        keyTypeParamSymbol: SymbolID,
        valueTypeParamSymbol: SymbolID
    ) -> TypeID {
        let entryName = interner.intern("Entry")
        let mapFQName = kotlinCollectionsPkg + [interner.intern("Map")]
        let entryFQName = mapFQName + [entryName]
        let entrySymbol: SymbolID
        if let existing = symbols.lookup(fqName: entryFQName) {
            entrySymbol = existing
        } else {
            let symbol = symbols.define(
                kind: .interface,
                name: entryName,
                fqName: entryFQName,
                declSite: nil,
                visibility: .public,
                flags: [.synthetic]
            )
            symbols.setParentSymbol(mapInterfaceSymbol, for: symbol)
            entrySymbol = symbol
        }

        let keyType = types.make(.typeParam(TypeParamType(symbol: keyTypeParamSymbol, nullability: .nonNull)))
        let valueType = types.make(.typeParam(TypeParamType(symbol: valueTypeParamSymbol, nullability: .nonNull)))
        types.setNominalTypeParameterSymbols([keyTypeParamSymbol, valueTypeParamSymbol], for: entrySymbol)
        types.setNominalTypeParameterVariances([.out, .out], for: entrySymbol)
        let receiverType = types.make(.classType(ClassType(
            classSymbol: entrySymbol,
            args: [.out(keyType), .out(valueType)],
            nullability: .nonNull
        )))

        func registerMember(
            name: String,
            returnType: TypeID,
            externalLinkName: String,
            flags: SymbolFlags = [.synthetic]
        ) {
            let memberName = interner.intern(name)
            let memberFQName = entryFQName + [memberName]
            guard symbols.lookup(fqName: memberFQName) == nil else { return }
            let memberSymbol = symbols.define(
                kind: .function,
                name: memberName,
                fqName: memberFQName,
                declSite: nil,
                visibility: .public,
                flags: flags
            )
            symbols.setParentSymbol(entrySymbol, for: memberSymbol)
            symbols.setExternalLinkName(externalLinkName, for: memberSymbol)
            symbols.setFunctionSignature(
                FunctionSignature(
                    receiverType: receiverType,
                    parameterTypes: [],
                    returnType: returnType,
                    typeParameterSymbols: [keyTypeParamSymbol, valueTypeParamSymbol],
                    classTypeParameterCount: 2
                ),
                for: memberSymbol
            )
        }

        registerMember(name: "component1", returnType: keyType, externalLinkName: "kk_pair_first", flags: [.synthetic, .operatorFunction])
        registerMember(name: "component2", returnType: valueType, externalLinkName: "kk_pair_second", flags: [.synthetic, .operatorFunction])
        registerMember(name: "key", returnType: keyType, externalLinkName: "kk_pair_first")
        registerMember(name: "value", returnType: valueType, externalLinkName: "kk_pair_second")

        return receiverType
    }

    private func registerSyntheticMutableMapStub(
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner,
        kotlinCollectionsPkg: [InternedString],
        mapInterfaceSymbol: SymbolID,
        keyTypeParamSymbol _: SymbolID,
        valueTypeParamSymbol _: SymbolID
    ) {
        let mutableMapName = interner.intern("MutableMap")
        let mutableMapFQName = kotlinCollectionsPkg + [mutableMapName]
        let mutableMapSymbol: SymbolID = if let existing = symbols.lookup(fqName: mutableMapFQName) {
            existing
        } else {
            symbols.define(
                kind: .interface,
                name: mutableMapName,
                fqName: mutableMapFQName,
                declSite: nil,
                visibility: .public,
                flags: [.synthetic]
            )
        }
        symbols.setDirectSupertypes([mapInterfaceSymbol], for: mutableMapSymbol)
        types.setNominalDirectSupertypes([mapInterfaceSymbol], for: mutableMapSymbol)

        let keyName = interner.intern("K")
        let valueName = interner.intern("V")
        let mutableKeyParamSymbol = symbols.define(
            kind: .typeParameter,
            name: keyName,
            fqName: mutableMapFQName + [keyName],
            declSite: nil,
            visibility: .private,
            flags: []
        )
        let mutableValueParamSymbol = symbols.define(
            kind: .typeParameter,
            name: valueName,
            fqName: mutableMapFQName + [valueName],
            declSite: nil,
            visibility: .private,
            flags: []
        )
        let keyType = types.make(.typeParam(TypeParamType(symbol: mutableKeyParamSymbol, nullability: .nonNull)))
        let valueType = types.make(.typeParam(TypeParamType(symbol: mutableValueParamSymbol, nullability: .nonNull)))
        types.setNominalTypeParameterSymbols([mutableKeyParamSymbol, mutableValueParamSymbol], for: mutableMapSymbol)
        types.setNominalTypeParameterVariances([.invariant, .invariant], for: mutableMapSymbol)
        symbols.setSupertypeTypeArgs([.out(keyType), .out(valueType)], for: mutableMapSymbol, supertype: mapInterfaceSymbol)
        types.setNominalSupertypeTypeArgs([.out(keyType), .out(valueType)], for: mutableMapSymbol, supertype: mapInterfaceSymbol)
        let receiverType = types.make(.classType(ClassType(
            classSymbol: mutableMapSymbol,
            args: [.invariant(keyType), .invariant(valueType)],
            nullability: .nonNull
        )))

        let getOrPutLambdaType = types.make(.functionType(FunctionType(
            params: [],
            returnType: valueType,
            isSuspend: false,
            nullability: .nonNull
        )))

        let mapParamType = types.make(.classType(ClassType(
            classSymbol: mapInterfaceSymbol,
            args: [.out(keyType), .out(valueType)],
            nullability: .nonNull
        )))

        let members: [(name: String, params: [TypeID], ret: TypeID, external: String, flags: SymbolFlags)] = [
            ("set", [keyType, valueType], types.unitType, "kk_mutable_map_put", [.synthetic, .operatorFunction]),
            ("put", [keyType, valueType], types.makeNullable(valueType), "kk_mutable_map_put", [.synthetic]),
            ("remove", [keyType], types.makeNullable(valueType), "kk_mutable_map_remove", [.synthetic]),
            ("clear", [], types.unitType, "kk_mutable_map_clear", [.synthetic]),
            ("getOrPut", [keyType, getOrPutLambdaType], valueType, "kk_mutable_map_getOrPut", [.synthetic, .inlineFunction]),
            ("putAll", [mapParamType], types.unitType, "kk_mutable_map_putAll", [.synthetic]),
        ]

        for member in members {
            let memberName = interner.intern(member.name)
            let memberFQName = mutableMapFQName + [memberName]
            guard symbols.lookup(fqName: memberFQName) == nil else { continue }
            let memberSymbol = symbols.define(
                kind: .function,
                name: memberName,
                fqName: memberFQName,
                declSite: nil,
                visibility: .public,
                flags: member.flags
            )
            symbols.setParentSymbol(mutableMapSymbol, for: memberSymbol)
            symbols.setExternalLinkName(member.external, for: memberSymbol)
            symbols.setFunctionSignature(
                FunctionSignature(
                    receiverType: receiverType,
                    parameterTypes: member.params,
                    returnType: member.ret,
                    typeParameterSymbols: [mutableKeyParamSymbol, mutableValueParamSymbol],
                    classTypeParameterCount: 2
                ),
                for: memberSymbol
            )
        }
    }

    private func registerListIndexedMembers(
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner,
        kotlinCollectionsPkg: [InternedString],
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

        // withIndex(): Iterable<IndexedValue<E>>
        let indexedValueSymbol = registerSyntheticIndexedValueStub(
            symbols: symbols, types: types, interner: interner,
            kotlinCollectionsPkg: kotlinCollectionsPkg
        )
        let indexedValueType = types.make(.classType(ClassType(
            classSymbol: indexedValueSymbol,
            args: [.out(listTypeParamType)],
            nullability: .nonNull
        )))
        let iterableSymbol = symbols.lookup(fqName: kotlinCollectionsPkg + [interner.intern("Iterable")]) ?? listInterfaceSymbol
        let iterableIndexedValueType = types.make(.classType(ClassType(
            classSymbol: iterableSymbol,
            args: [.out(indexedValueType)],
            nullability: .nonNull
        )))
        let listSymbol = listInterfaceSymbol

        let withIndexName = interner.intern("withIndex")
        let withIndexFQName = listFQName + [withIndexName]
        if symbols.lookup(fqName: withIndexFQName) == nil {
            let memberSymbol = symbols.define(
                kind: .function,
                name: withIndexName,
                fqName: withIndexFQName,
                declSite: nil,
                visibility: .public,
                flags: [.synthetic]
            )
            symbols.setParentSymbol(listInterfaceSymbol, for: memberSymbol)
            symbols.setExternalLinkName("kk_list_withIndex", for: memberSymbol)
            symbols.setFunctionSignature(
                FunctionSignature(
                    receiverType: receiverType,
                    parameterTypes: [],
                    returnType: iterableIndexedValueType,
                    typeParameterSymbols: [listTypeParamSymbol],
                    classTypeParameterCount: 1
                ),
                for: memberSymbol
            )
        }

        // forEachIndexed(action: (Int, E) -> Unit)
        let forEachIndexedName = interner.intern("forEachIndexed")
        let forEachIndexedFQName = listFQName + [forEachIndexedName]
        if symbols.lookup(fqName: forEachIndexedFQName) == nil {
            let actionType = types.make(.functionType(FunctionType(
                params: [types.intType, listTypeParamType],
                returnType: types.unitType,
                isSuspend: false,
                nullability: .nonNull
            )))
            let memberSymbol = symbols.define(
                kind: .function,
                name: forEachIndexedName,
                fqName: forEachIndexedFQName,
                declSite: nil,
                visibility: .public,
                flags: [.synthetic, .inlineFunction]
            )
            symbols.setParentSymbol(listInterfaceSymbol, for: memberSymbol)
            symbols.setExternalLinkName("kk_list_forEachIndexed", for: memberSymbol)
            symbols.setFunctionSignature(
                FunctionSignature(
                    receiverType: receiverType,
                    parameterTypes: [actionType],
                    returnType: types.unitType,
                    typeParameterSymbols: [listTypeParamSymbol],
                    classTypeParameterCount: 1
                ),
                for: memberSymbol
            )
        }

        // mapIndexed(transform: (Int, E) -> R): List<R>
        let mapIndexedName = interner.intern("mapIndexed")
        let mapIndexedFQName = listFQName + [mapIndexedName]
        if symbols.lookup(fqName: mapIndexedFQName) == nil {
            // mapIndexed is tricky because of the generic R.
            // For synthetic stub, we might simplify to List<Any?> or just have it resolve via fallback if generic R is hard to define here.
            // But let's try to define a local type parameter R for the function.
            let rName = interner.intern("R")
            let rFQName = mapIndexedFQName + [rName]
            let rSymbol = symbols.define(
                kind: .typeParameter,
                name: rName,
                fqName: rFQName,
                declSite: nil,
                visibility: .private,
                flags: []
            )
            let rType = types.make(.typeParam(TypeParamType(symbol: rSymbol, nullability: .nonNull)))

            let transformType = types.make(.functionType(FunctionType(
                params: [types.intType, listTypeParamType],
                returnType: rType,
                isSuspend: false,
                nullability: .nonNull
            )))
            let listRType = types.make(.classType(ClassType(
                classSymbol: listSymbol,
                args: [.out(rType)],
                nullability: .nonNull
            )))

            let memberSymbol = symbols.define(
                kind: .function,
                name: mapIndexedName,
                fqName: mapIndexedFQName,
                declSite: nil,
                visibility: .public,
                flags: [.synthetic, .inlineFunction]
            )
            symbols.setParentSymbol(listInterfaceSymbol, for: memberSymbol)
            symbols.setExternalLinkName("kk_list_mapIndexed", for: memberSymbol)
            symbols.setFunctionSignature(
                FunctionSignature(
                    receiverType: receiverType,
                    parameterTypes: [transformType],
                    returnType: listRType,
                    typeParameterSymbols: [listTypeParamSymbol, rSymbol],
                    classTypeParameterCount: 1 // Only List's E is class-level
                ),
                for: memberSymbol
            )
        }
    }

    private func registerSyntheticIndexedValueStub(
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner,
        kotlinCollectionsPkg: [InternedString]
    ) -> SymbolID {
        let name = interner.intern("IndexedValue")
        let fqName = kotlinCollectionsPkg + [name]
        if let existing = symbols.lookup(fqName: fqName) {
            return existing
        }
        let symbol = symbols.define(
            kind: .class,
            name: name,
            fqName: fqName,
            declSite: nil,
            visibility: .public,
            flags: [.synthetic, .dataType]
        )
        let tName = interner.intern("T")
        let tFQName = fqName + [tName]
        let tSymbol = symbols.define(
            kind: .typeParameter,
            name: tName,
            fqName: tFQName,
            declSite: nil,
            visibility: .private,
            flags: []
        )
        let tType = types.make(.typeParam(TypeParamType(symbol: tSymbol, nullability: .nonNull)))
        types.setNominalTypeParameterSymbols([tSymbol], for: symbol)
        types.setNominalTypeParameterVariances([.out], for: symbol)

        // Add index: Int and value: T properties (component1, component2 for destructuring)
        let receiverType = types.make(.classType(ClassType(
            classSymbol: symbol,
            args: [.out(tType)],
            nullability: .nonNull
        )))

        func registerComponent(name: String, ret: TypeID, externalLinkName: String) {
            let mName = interner.intern(name)
            let mFQName = fqName + [mName]
            let mSymbol = symbols.define(
                kind: .function,
                name: mName,
                fqName: mFQName,
                declSite: nil,
                visibility: .public,
                flags: [.synthetic, .operatorFunction]
            )
            symbols.setParentSymbol(symbol, for: mSymbol)
            symbols.setExternalLinkName(externalLinkName, for: mSymbol)
            symbols.setFunctionSignature(
                FunctionSignature(
                    receiverType: receiverType,
                    parameterTypes: [],
                    returnType: ret,
                    typeParameterSymbols: [tSymbol],
                    classTypeParameterCount: 1
                ),
                for: mSymbol
            )
        }

        func registerPropertyGetter(name: String, ret: TypeID, externalLinkName: String) {
            let mName = interner.intern(name)
            let mFQName = fqName + [mName]
            let mSymbol = symbols.define(
                kind: .property,
                name: mName,
                fqName: mFQName,
                declSite: nil,
                visibility: .public,
                flags: [.synthetic]
            )
            symbols.setParentSymbol(symbol, for: mSymbol)
            symbols.setExternalLinkName(externalLinkName, for: mSymbol)
            symbols.setPropertyType(ret, for: mSymbol)
        }

        registerComponent(name: "component1", ret: types.intType, externalLinkName: "kk_pair_first")
        registerComponent(name: "component2", ret: tType, externalLinkName: "kk_pair_second")
        registerPropertyGetter(name: "index", ret: types.intType, externalLinkName: "kk_pair_first")
        registerPropertyGetter(name: "value", ret: tType, externalLinkName: "kk_pair_second")

        return symbol
    }

    // MARK: - ArrayDeque (STDLIB-240)

    private func registerSyntheticArrayDequeStub(
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner,
        kotlinCollectionsPkg: [InternedString]
    ) {
        let arrayDequeName = interner.intern("ArrayDeque")
        let arrayDequeFQName = kotlinCollectionsPkg + [arrayDequeName]
        let arrayDequeSymbol: SymbolID = if let existing = symbols.lookup(fqName: arrayDequeFQName) {
            existing
        } else {
            symbols.define(
                kind: .class,
                name: arrayDequeName,
                fqName: arrayDequeFQName,
                declSite: nil,
                visibility: .public,
                flags: [.synthetic]
            )
        }

        // Define type parameter E for ArrayDeque<E>
        let typeParamName = interner.intern("E")
        let typeParamFQName = arrayDequeFQName + [typeParamName]
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
        types.setNominalTypeParameterSymbols([typeParamSymbol], for: arrayDequeSymbol)
        types.setNominalTypeParameterVariances([.invariant], for: arrayDequeSymbol)

        let receiverType = types.make(.classType(ClassType(
            classSymbol: arrayDequeSymbol,
            args: [.invariant(typeParamType)],
            nullability: .nonNull
        )))

        // Constructor: ArrayDeque() → kk_arraydeque_new
        let initName = interner.intern("<init>")
        let initFQName = arrayDequeFQName + [initName]
        if symbols.lookup(fqName: initFQName) == nil {
            let initSymbol = symbols.define(
                kind: .constructor,
                name: initName,
                fqName: initFQName,
                declSite: nil,
                visibility: .public,
                flags: [.synthetic]
            )
            symbols.setParentSymbol(arrayDequeSymbol, for: initSymbol)
            symbols.setExternalLinkName("kk_arraydeque_new", for: initSymbol)
            symbols.setFunctionSignature(
                FunctionSignature(
                    receiverType: nil,
                    parameterTypes: [],
                    returnType: receiverType,
                    typeParameterSymbols: [typeParamSymbol],
                    classTypeParameterCount: 1
                ),
                for: initSymbol
            )
        }

        // addFirst(element: E): Unit
        registerArrayDequeMember(
            symbols: symbols, types: types, interner: interner,
            fqName: arrayDequeFQName, parentSymbol: arrayDequeSymbol,
            receiverType: receiverType, typeParamSymbol: typeParamSymbol,
            memberName: "addFirst", externalName: "kk_arraydeque_addFirst",
            parameterTypes: [typeParamType], returnType: types.unitType
        )

        // addLast(element: E): Unit
        registerArrayDequeMember(
            symbols: symbols, types: types, interner: interner,
            fqName: arrayDequeFQName, parentSymbol: arrayDequeSymbol,
            receiverType: receiverType, typeParamSymbol: typeParamSymbol,
            memberName: "addLast", externalName: "kk_arraydeque_addLast",
            parameterTypes: [typeParamType], returnType: types.unitType
        )

        // removeFirst(): E (can throw)
        registerArrayDequeMember(
            symbols: symbols, types: types, interner: interner,
            fqName: arrayDequeFQName, parentSymbol: arrayDequeSymbol,
            receiverType: receiverType, typeParamSymbol: typeParamSymbol,
            memberName: "removeFirst", externalName: "kk_arraydeque_removeFirst",
            parameterTypes: [], returnType: typeParamType
        )

        // removeLast(): E (can throw)
        registerArrayDequeMember(
            symbols: symbols, types: types, interner: interner,
            fqName: arrayDequeFQName, parentSymbol: arrayDequeSymbol,
            receiverType: receiverType, typeParamSymbol: typeParamSymbol,
            memberName: "removeLast", externalName: "kk_arraydeque_removeLast",
            parameterTypes: [], returnType: typeParamType
        )

        // first(): E (can throw)
        registerArrayDequeMember(
            symbols: symbols, types: types, interner: interner,
            fqName: arrayDequeFQName, parentSymbol: arrayDequeSymbol,
            receiverType: receiverType, typeParamSymbol: typeParamSymbol,
            memberName: "first", externalName: "kk_arraydeque_first",
            parameterTypes: [], returnType: typeParamType
        )

        // last(): E (can throw)
        registerArrayDequeMember(
            symbols: symbols, types: types, interner: interner,
            fqName: arrayDequeFQName, parentSymbol: arrayDequeSymbol,
            receiverType: receiverType, typeParamSymbol: typeParamSymbol,
            memberName: "last", externalName: "kk_arraydeque_last",
            parameterTypes: [], returnType: typeParamType
        )

        // size: Int (property-like)
        registerArrayDequeMember(
            symbols: symbols, types: types, interner: interner,
            fqName: arrayDequeFQName, parentSymbol: arrayDequeSymbol,
            receiverType: receiverType, typeParamSymbol: typeParamSymbol,
            memberName: "size", externalName: "kk_arraydeque_size",
            parameterTypes: [], returnType: types.intType
        )

        // isEmpty(): Boolean
        registerArrayDequeMember(
            symbols: symbols, types: types, interner: interner,
            fqName: arrayDequeFQName, parentSymbol: arrayDequeSymbol,
            receiverType: receiverType, typeParamSymbol: typeParamSymbol,
            memberName: "isEmpty", externalName: "kk_arraydeque_isEmpty",
            parameterTypes: [], returnType: types.booleanType
        )

        // toString(): String
        registerArrayDequeMember(
            symbols: symbols, types: types, interner: interner,
            fqName: arrayDequeFQName, parentSymbol: arrayDequeSymbol,
            receiverType: receiverType, typeParamSymbol: typeParamSymbol,
            memberName: "toString", externalName: "kk_arraydeque_toString",
            parameterTypes: [], returnType: types.stringType
        )
    }

    private func registerArrayDequeMember(
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner,
        fqName: [InternedString],
        parentSymbol: SymbolID,
        receiverType: TypeID,
        typeParamSymbol: SymbolID,
        memberName: String,
        externalName: String,
        parameterTypes: [TypeID],
        returnType: TypeID
    ) {
        let internedName = interner.intern(memberName)
        let memberFQName = fqName + [internedName]
        guard symbols.lookup(fqName: memberFQName) == nil else { return }
        let memberSymbol = symbols.define(
            kind: .function,
            name: internedName,
            fqName: memberFQName,
            declSite: nil,
            visibility: .public,
            flags: [.synthetic, .operatorFunction]
        )
        symbols.setParentSymbol(parentSymbol, for: memberSymbol)
        symbols.setExternalLinkName(externalName, for: memberSymbol)
        symbols.setFunctionSignature(
            FunctionSignature(
                receiverType: receiverType,
                parameterTypes: parameterTypes,
                returnType: returnType,
                typeParameterSymbols: [typeParamSymbol],
                classTypeParameterCount: 1
            ),
            for: memberSymbol
        )
    }

    /// Create a type parameter `R` with upper bound `Comparable<R>` for use in
    /// selector-based HOF stubs (sortedBy, sortedByDescending, maxByOrNull, etc.).
    ///
    /// When `Comparable` is not yet registered, the `R` parameter is omitted and
    /// `selectorReturnType` falls back to `Any`, avoiding an unconstrained generic.
    ///
    /// - Returns: A tuple of `(rSymbol, rType, comparableRBounds)` when the
    ///   Comparable interface is available, or `nil` when it is not.
    private func makeComparableTypeParam(
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
            args: [.invariant(rType)],
            nullability: .nonNull
        )))]
        return (rSymbol, rType, comparableRBounds)
    }

    // MARK: - Collection Type Aliases (STDLIB-560)

    /// Register `ArrayList<E>`, `LinkedList<E>`, `HashMap<K,V>`, `HashSet<E>`, `LinkedHashMap<K,V>`, `LinkedHashSet<E>`
    /// as type aliases pointing to their corresponding mutable collection types.
    private func registerSyntheticCollectionTypeAliases(
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner,
        kotlinCollectionsPkg: [InternedString]
    ) {
        // ArrayList<E> → MutableList<E>
        registerSingleTypeParamCollectionAlias(
            aliasName: "ArrayList",
            targetName: "MutableList",
            symbols: symbols, types: types, interner: interner,
            kotlinCollectionsPkg: kotlinCollectionsPkg
        )

        // LinkedList<E> → MutableList<E>
        registerSingleTypeParamCollectionAlias(
            aliasName: "LinkedList",
            targetName: "MutableList",
            symbols: symbols, types: types, interner: interner,
            kotlinCollectionsPkg: kotlinCollectionsPkg
        )

        // HashSet<E> → MutableSet<E>
        registerSingleTypeParamCollectionAlias(
            aliasName: "HashSet",
            targetName: "MutableSet",
            symbols: symbols, types: types, interner: interner,
            kotlinCollectionsPkg: kotlinCollectionsPkg
        )

        // LinkedHashSet<E> → MutableSet<E>
        registerSingleTypeParamCollectionAlias(
            aliasName: "LinkedHashSet",
            targetName: "MutableSet",
            symbols: symbols, types: types, interner: interner,
            kotlinCollectionsPkg: kotlinCollectionsPkg
        )

        // HashMap<K, V> → MutableMap<K, V>
        registerTwoTypeParamCollectionAlias(
            aliasName: "HashMap",
            targetName: "MutableMap",
            symbols: symbols, types: types, interner: interner,
            kotlinCollectionsPkg: kotlinCollectionsPkg
        )

        // LinkedHashMap<K, V> → MutableMap<K, V>
        registerTwoTypeParamCollectionAlias(
            aliasName: "LinkedHashMap",
            targetName: "MutableMap",
            symbols: symbols, types: types, interner: interner,
            kotlinCollectionsPkg: kotlinCollectionsPkg
        )
    }

    /// Register a type alias with one type parameter (e.g. `ArrayList<E> = MutableList<E>`).
    private func registerSingleTypeParamCollectionAlias(
        aliasName: String,
        targetName: String,
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner,
        kotlinCollectionsPkg: [InternedString]
    ) {
        let internedAlias = interner.intern(aliasName)
        let aliasFQName = kotlinCollectionsPkg + [internedAlias]
        guard symbols.lookup(fqName: aliasFQName) == nil else { return }

        // Validate target symbol exists before registering alias
        let internedTarget = interner.intern(targetName)
        let targetFQName = kotlinCollectionsPkg + [internedTarget]
        guard let targetSymbol = symbols.lookup(fqName: targetFQName) else {
            assertionFailure("Synthetic collection type alias '\(aliasName)': target '\(targetName)' not found in symbol table")
            return
        }

        let aliasSymbol = symbols.define(
            kind: .typeAlias,
            name: internedAlias,
            fqName: aliasFQName,
            declSite: nil,
            visibility: .public,
            flags: [.synthetic]
        )

        // Define type parameter E
        let typeParamName = interner.intern("E")
        let typeParamFQName = aliasFQName + [typeParamName]
        let typeParamSymbol = symbols.define(
            kind: .typeParameter,
            name: typeParamName,
            fqName: typeParamFQName,
            declSite: nil,
            visibility: .private,
            flags: []
        )
        symbols.setTypeAliasTypeParameters([typeParamSymbol], for: aliasSymbol)

        // Build underlying type: TargetType<E>
        let typeParamType = types.make(.typeParam(TypeParamType(
            symbol: typeParamSymbol, nullability: .nonNull
        )))
        let underlyingType = types.make(.classType(ClassType(
            classSymbol: targetSymbol,
            args: [.invariant(typeParamType)],
            nullability: .nonNull
        )))
        symbols.setTypeAliasUnderlyingType(underlyingType, for: aliasSymbol)
    }

    /// Register a type alias with two type parameters (e.g. `HashMap<K, V> = MutableMap<K, V>`).
    private func registerTwoTypeParamCollectionAlias(
        aliasName: String,
        targetName: String,
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner,
        kotlinCollectionsPkg: [InternedString]
    ) {
        let internedAlias = interner.intern(aliasName)
        let aliasFQName = kotlinCollectionsPkg + [internedAlias]
        guard symbols.lookup(fqName: aliasFQName) == nil else { return }

        // Validate target symbol exists before registering alias
        let internedTarget = interner.intern(targetName)
        let targetFQName = kotlinCollectionsPkg + [internedTarget]
        guard let targetSymbol = symbols.lookup(fqName: targetFQName) else {
            assertionFailure("Synthetic collection type alias '\(aliasName)': target '\(targetName)' not found in symbol table")
            return
        }

        let aliasSymbol = symbols.define(
            kind: .typeAlias,
            name: internedAlias,
            fqName: aliasFQName,
            declSite: nil,
            visibility: .public,
            flags: [.synthetic]
        )

        // Define type parameters K, V
        let keyParamName = interner.intern("K")
        let valueParamName = interner.intern("V")
        let keyParamFQName = aliasFQName + [keyParamName]
        let valueParamFQName = aliasFQName + [valueParamName]
        let keyParamSymbol = symbols.define(
            kind: .typeParameter,
            name: keyParamName,
            fqName: keyParamFQName,
            declSite: nil,
            visibility: .private,
            flags: []
        )
        let valueParamSymbol = symbols.define(
            kind: .typeParameter,
            name: valueParamName,
            fqName: valueParamFQName,
            declSite: nil,
            visibility: .private,
            flags: []
        )
        symbols.setTypeAliasTypeParameters([keyParamSymbol, valueParamSymbol], for: aliasSymbol)

        // Build underlying type: TargetType<K, V>
        let keyType = types.make(.typeParam(TypeParamType(
            symbol: keyParamSymbol, nullability: .nonNull
        )))
        let valueType = types.make(.typeParam(TypeParamType(
            symbol: valueParamSymbol, nullability: .nonNull
        )))
        let underlyingType = types.make(.classType(ClassType(
            classSymbol: targetSymbol,
            args: [.invariant(keyType), .invariant(valueType)],
            nullability: .nonNull
        )))
        symbols.setTypeAliasUnderlyingType(underlyingType, for: aliasSymbol)
    }

    // MARK: - Array<T> and primitive arrays (TYPE-103)

    private func registerSyntheticArrayStubs(
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner
    ) {
        let kotlinPkg: [InternedString] = [interner.intern("kotlin")]

        // --- kotlin.Array<T> ---
        let arrayFQName = kotlinPkg + [interner.intern("Array")]
        let arraySymbol: SymbolID = if let existing = symbols.lookup(fqName: arrayFQName) {
            existing
        } else {
            symbols.define(
                kind: .class,
                name: interner.intern("Array"),
                fqName: arrayFQName,
                declSite: nil,
                visibility: .public,
                flags: [.synthetic]
            )
        }
        let tParamName = interner.intern("T")
        let tParamSymbol = symbols.lookup(fqName: arrayFQName + [tParamName]) ?? symbols.define(
            kind: .typeParameter,
            name: tParamName,
            fqName: arrayFQName + [tParamName],
            declSite: nil,
            visibility: .private,
            flags: []
        )
        types.setNominalTypeParameterSymbols([tParamSymbol], for: arraySymbol)
        types.setNominalTypeParameterVariances([.invariant], for: arraySymbol)

        // Register size property for Array<T>
        let sizeReturnType = types.intType
        let sizeName = interner.intern("size")
        let sizeFQName = arrayFQName + [sizeName]
        if symbols.lookup(fqName: sizeFQName) == nil {
            let sizeSym = symbols.define(
                kind: .property,
                name: sizeName,
                fqName: sizeFQName,
                declSite: nil,
                visibility: .public,
                flags: [.synthetic]
            )
            symbols.setParentSymbol(arraySymbol, for: sizeSym)
            symbols.setPropertyType(sizeReturnType, for: sizeSym)
        }

        // --- Primitive array types: IntArray, LongArray, etc. ---
        let primitiveArrayNames = [
            "IntArray",
            "LongArray",
            "DoubleArray",
            "FloatArray",
            "BooleanArray",
            "CharArray",
            "ByteArray",
            "ShortArray",
        ]
        for name in primitiveArrayNames {
            let primName = interner.intern(name)
            let fqName = kotlinPkg + [primName]
            // Ensure the class symbol exists, whether previously defined or not.
            let sym: SymbolID = if let existing = symbols.lookup(fqName: fqName) {
                existing
            } else {
                symbols.define(
                    kind: .class,
                    name: primName,
                    fqName: fqName,
                    declSite: nil,
                    visibility: .public,
                    flags: [.synthetic]
                )
            }
            // Register size property independently of class existence,
            // so that even if the class was defined elsewhere without size,
            // we still add the property.
            let primSizeFQName = fqName + [sizeName]
            if symbols.lookup(fqName: primSizeFQName) == nil {
                let primSizeSym = symbols.define(
                    kind: .property,
                    name: sizeName,
                    fqName: primSizeFQName,
                    declSite: nil,
                    visibility: .public,
                    flags: [.synthetic]
                )
                symbols.setParentSymbol(sym, for: primSizeSym)
                symbols.setPropertyType(sizeReturnType, for: primSizeSym)
            }
        }
    }
}
