// swiftlint:disable file_length
import Foundation

// Collection type stubs (List<E>, MutableList<E>) for kotlin.collections,
// and Comparable<T> for kotlin.
// Split from DataFlowSemaPhase+HeaderHelpers.swift to stay within file-length limits.

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

        let listInterfaceSymbol = registerSyntheticListStub(
            symbols: symbols, types: types, interner: interner,
            kotlinCollectionsPkg: kotlinCollectionsPkg
        )

        registerSyntheticMutableListStub(
            symbols: symbols, types: types, interner: interner,
            kotlinCollectionsPkg: kotlinCollectionsPkg,
            listInterfaceSymbol: listInterfaceSymbol
        )

        let setInterfaceSymbol = registerSyntheticSetStub(
            symbols: symbols, types: types, interner: interner,
            kotlinCollectionsPkg: kotlinCollectionsPkg
        )

        registerSyntheticMutableSetStub(
            symbols: symbols, types: types, interner: interner,
            kotlinCollectionsPkg: kotlinCollectionsPkg,
            setInterfaceSymbol: setInterfaceSymbol
        )
        registerListConversionMembers(
            symbols: symbols, types: types, interner: interner,
            kotlinCollectionsPkg: kotlinCollectionsPkg,
            listInterfaceSymbol: listInterfaceSymbol
        )

        let mapSymbols = registerSyntheticMapStub(
            symbols: symbols, types: types, interner: interner,
            kotlinCollectionsPkg: kotlinCollectionsPkg
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
    }

    /// Register `kotlin.collections.List<E>` interface stub with `operator fun get(index: Int): E`.
    private func registerSyntheticListStub(
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner,
        kotlinCollectionsPkg: [InternedString]
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

        registerListGetOperator(
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
            flags: [.synthetic]
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
            flags: [.synthetic]
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
            flags: [.synthetic]
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
        registerMember(name: "sorted", parameterTypes: [], externalLinkName: "kk_list_sorted")
        registerMember(name: "distinct", parameterTypes: [], externalLinkName: "kk_list_distinct")
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
        registerSimpleMember(name: "maxOrNull", returnType: nullableElementType, externalLinkName: "kk_list_maxOrNull")
        registerSimpleMember(name: "minOrNull", returnType: nullableElementType, externalLinkName: "kk_list_minOrNull")

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
                flags: [.synthetic]
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
    }

    private func registerListConversionMembers(
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner,
        kotlinCollectionsPkg: [InternedString],
        listInterfaceSymbol: SymbolID
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
    }

    /// Register `kotlin.collections.MutableList<E>` interface stub with `operator fun set(index: Int, element: E): E`.
    private func registerSyntheticMutableListStub(
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner,
        kotlinCollectionsPkg: [InternedString],
        listInterfaceSymbol: SymbolID
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
        symbols.setSupertypeTypeArgs([.invariant(mlTypeParamType)], for: mutableListInterfaceSymbol, supertype: listInterfaceSymbol)
        types.setNominalSupertypeTypeArgs([.invariant(mlTypeParamType)], for: mutableListInterfaceSymbol, supertype: listInterfaceSymbol)

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
        symbols.setExternalLinkName("kk_array_set", for: mlSetSymbol)
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
            flags: [.synthetic]
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
            flags: [.synthetic]
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

    private func registerSyntheticSetStub(
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner,
        kotlinCollectionsPkg: [InternedString]
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

        registerSetContainsMember(
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

    private func registerSyntheticMutableSetStub(
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner,
        kotlinCollectionsPkg: [InternedString],
        setInterfaceSymbol: SymbolID
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

        let members: [(name: String, params: [TypeID], ret: TypeID, external: String, flags: SymbolFlags)] = [
            ("set", [keyType, valueType], types.unitType, "kk_mutable_map_put", [.synthetic, .operatorFunction]),
            ("put", [keyType, valueType], types.makeNullable(valueType), "kk_mutable_map_put", [.synthetic]),
            ("remove", [keyType], types.makeNullable(valueType), "kk_mutable_map_remove", [.synthetic]),
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

        // withIndex(): List<IndexedValue<E>>
        let indexedValueSymbol = registerSyntheticIndexedValueStub(
            symbols: symbols, types: types, interner: interner,
            kotlinCollectionsPkg: kotlinCollectionsPkg
        )
        let indexedValueType = types.make(.classType(ClassType(
            classSymbol: indexedValueSymbol,
            args: [.out(listTypeParamType)],
            nullability: .nonNull
        )))
        let listSymbol = listInterfaceSymbol
        let listIndexedValueType = types.make(.classType(ClassType(
            classSymbol: listSymbol,
            args: [.out(indexedValueType)],
            nullability: .nonNull
        )))

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
                    returnType: listIndexedValueType,
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
                flags: [.synthetic]
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
                flags: [.synthetic]
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
            kind: .interface,
            name: name,
            fqName: fqName,
            declSite: nil,
            visibility: .public,
            flags: [.synthetic]
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
                kind: .function, // For synthetic stub, we treat it as a function/getter
                name: mName,
                fqName: mFQName,
                declSite: nil,
                visibility: .public,
                flags: [.synthetic]
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

        registerComponent(name: "component1", ret: types.intType, externalLinkName: "kk_pair_first")
        registerComponent(name: "component2", ret: tType, externalLinkName: "kk_pair_second")
        registerPropertyGetter(name: "index", ret: types.intType, externalLinkName: "kk_pair_first")
        registerPropertyGetter(name: "value", ret: tType, externalLinkName: "kk_pair_second")

        return symbol
    }
}
