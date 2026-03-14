// swiftlint:disable file_length
import Foundation

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
            mapInterfaceSymbol: mapSymbols.mapSymbol
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

        registerFunctionMember(
            name: "toList",
            returnType: types.anyType,
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

        registerFunctionMember(name: "component1", returnType: aType, externalLinkName: "kk_triple_first", flags: [.synthetic, .operatorFunction])
        registerFunctionMember(name: "component2", returnType: bType, externalLinkName: "kk_triple_second", flags: [.synthetic, .operatorFunction])
        registerFunctionMember(name: "component3", returnType: cType, externalLinkName: "kk_triple_third", flags: [.synthetic, .operatorFunction])
        registerPropertyMember(name: "first", propertyType: aType, externalLinkName: "kk_triple_first")
        registerPropertyMember(name: "second", propertyType: bType, externalLinkName: "kk_triple_second")
        registerPropertyMember(name: "third", propertyType: cType, externalLinkName: "kk_triple_third")
        registerFunctionMember(name: "toList", returnType: types.anyType, externalLinkName: "kk_triple_toList", flags: [.synthetic])
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
        return collectionInterfaceSymbol
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
        return iterableInterfaceSymbol
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
            listTypeParamType: listTypeParamType
        )
        registerListJoinToStringMember(
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
        listTypeParamType: TypeID
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

        func registerMember(
            name: String,
            parameterTypes: [TypeID],
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
                    parameterTypes: parameterTypes,
                    returnType: listReturnType,
                    typeParameterSymbols: [listTypeParamSymbol],
                    classTypeParameterCount: 1
                ),
                for: memberSymbol
            )
        }

        registerMember(name: "take", parameterTypes: [types.intType], externalLinkName: "kk_list_take")
        registerMember(name: "drop", parameterTypes: [types.intType], externalLinkName: "kk_list_drop")
        registerMember(name: "reversed", parameterTypes: [], externalLinkName: "kk_list_reversed")
        registerMember(name: "asReversed", parameterTypes: [], externalLinkName: "kk_list_reversed")
        registerMember(name: "sorted", parameterTypes: [], externalLinkName: "kk_list_sorted")
        registerMember(name: "distinct", parameterTypes: [], externalLinkName: "kk_list_distinct")
        registerMember(name: "shuffled", parameterTypes: [], externalLinkName: "kk_list_shuffled")
        registerMember(name: "flatten", parameterTypes: [], externalLinkName: "kk_list_flatten")
        registerMember(name: "chunked", parameterTypes: [types.intType], externalLinkName: "kk_list_chunked")
        registerMember(name: "windowed", parameterTypes: [types.intType, types.intType], externalLinkName: "kk_list_windowed")
        registerMember(name: "sortedDescending", parameterTypes: [], externalLinkName: "kk_list_sortedDescending")
        registerMember(name: "subList", parameterTypes: [types.intType, types.intType], externalLinkName: "kk_list_subList")
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
                let returnType = returnTypeBuilder(rType)
                let selectorType = types.make(.functionType(FunctionType(
                    params: [listTypeParamType],
                    returnType: rType,
                    isSuspend: false,
                    nullability: .nonNull
                )))
                let comparableRBounds: [TypeID] = if let comparableSymbol = types.comparableInterfaceSymbol {
                    [types.make(.classType(ClassType(
                        classSymbol: comparableSymbol,
                        args: [.invariant(rType)],
                        nullability: .nonNull
                    )))]
                } else {
                    []
                }
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
                        typeParameterSymbols: [listTypeParamSymbol, rSymbol],
                        typeParameterUpperBoundsList: [[], comparableRBounds],
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

        // sortedByDescending (HOF, selector lambda)
        let sortedByDescendingName = interner.intern("sortedByDescending")
        let sortedByDescendingFQName = listFQName + [sortedByDescendingName]
        if symbols.lookup(fqName: sortedByDescendingFQName) == nil {
            let selectorType = types.make(.functionType(FunctionType(
                params: [listTypeParamType],
                returnType: types.anyType,
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
                    typeParameterSymbols: [listTypeParamSymbol],
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
            // Return type is Pair<List<T>, List<T>> — use Any for now, refined by inference
            symbols.setFunctionSignature(
                FunctionSignature(
                    receiverType: receiverType,
                    parameterTypes: [predicateType2],
                    returnType: types.anyType,
                    typeParameterSymbols: [listTypeParamSymbol],
                    classTypeParameterCount: 1
                ),
                for: memberSymbol
            )
        }
    }

    private func registerListConversionMembers(
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner,
        kotlinCollectionsPkg: [InternedString],
        listInterfaceSymbol: SymbolID,
        mapInterfaceSymbol: SymbolID
    ) {
        guard let listTypeParamSymbol = symbols.lookup(
            fqName: kotlinCollectionsPkg + [interner.intern("List"), interner.intern("E")]
        ),
            let mutableListSymbol = symbols.lookup(
                fqName: kotlinCollectionsPkg + [interner.intern("MutableList")]
            ),
            let setInterfaceSymbol = symbols.lookup(
                fqName: kotlinCollectionsPkg + [interner.intern("Set")]
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
            flags: [.synthetic, .operatorFunction]
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
        let selectorType = types.make(.functionType(FunctionType(
            params: [mlTypeParamType],
            returnType: types.anyType,
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
                typeParameterSymbols: [mlTypeParamSymbol],
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
        let selectorType = types.make(.functionType(FunctionType(
            params: [mlTypeParamType],
            returnType: types.anyType,
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
                typeParameterSymbols: [mlTypeParamSymbol],
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
            flags: [.synthetic, .operatorFunction]
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
            typeParamType: typeParamType
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
        typeParamType: TypeID
    ) {
        let memberName = interner.intern("containsAll")
        let memberFQName = setFQName + [memberName]
        guard symbols.lookup(fqName: memberFQName) == nil else { return }
        let receiverType = types.make(.classType(ClassType(
            classSymbol: setInterfaceSymbol,
            args: [.out(typeParamType)],
            nullability: .nonNull
        )))
        let collectionType = types.anyType
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
        let keyType = types.make(.typeParam(TypeParamType(symbol: keyParamSymbol, nullability: .nonNull)))
        let valueType = types.make(.typeParam(TypeParamType(symbol: valueParamSymbol, nullability: .nonNull)))
        let receiverType = types.make(.classType(ClassType(
            classSymbol: mapSymbol,
            args: [.out(keyType), .out(valueType)],
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

        let maxByOrNullLambdaType = types.make(.functionType(FunctionType(
            params: [entryType],
            returnType: types.anyType,
            isSuspend: false,
            nullability: .nonNull
        )))
        let nullableEntryType = types.makeNullable(entryType)
        registerMember(
            name: "maxByOrNull",
            externalLinkName: "kk_map_maxByOrNull",
            parameterTypes: [maxByOrNullLambdaType],
            returnType: nullableEntryType,
            typeParameterSymbols: [keyTypeParamSymbol, valueTypeParamSymbol],
            flags: [.synthetic, .inlineFunction]
        )

        registerMember(
            name: "minByOrNull",
            externalLinkName: "kk_map_minByOrNull",
            parameterTypes: [maxByOrNullLambdaType],
            returnType: nullableEntryType,
            typeParameterSymbols: [keyTypeParamSymbol, valueTypeParamSymbol],
            flags: [.synthetic, .inlineFunction]
        )
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

        let members: [(name: String, params: [TypeID], ret: TypeID, external: String, flags: SymbolFlags)] = [
            ("set", [keyType, valueType], types.unitType, "kk_mutable_map_put", [.synthetic, .operatorFunction]),
            ("put", [keyType, valueType], types.makeNullable(valueType), "kk_mutable_map_put", [.synthetic]),
            ("remove", [keyType], types.makeNullable(valueType), "kk_mutable_map_remove", [.synthetic]),
            ("getOrPut", [keyType, getOrPutLambdaType], valueType, "kk_mutable_map_getOrPut", [.synthetic, .inlineFunction]),
            ("putAll", [types.make(.classType(ClassType(classSymbol: mapInterfaceSymbol, args: [.invariant(keyType), .invariant(valueType)], nullability: .nonNull)))], types.unitType, "kk_mutable_map_putAll", [.synthetic]),
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
}
