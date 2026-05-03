import Foundation

/// Synthetic stdlib stubs split from `HeaderHelpers+SyntheticComparableAndCollectionStubs.swift`:
/// List<E> interface and read-only member registrations (iterators, transform, aggregate, conversion).
///
/// Split out to isolate merge conflicts between parallel stdlib PRs adding new
/// entries to this package.
extension DataFlowSemaPhase {

    func registerSyntheticListStub(
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
            listTypeParamType: listTypeParamType,
            collectionInterfaceSymbol: collectionInterfaceSymbol
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

    /// Register `MutableListIterator<T>` extending `ListIterator<T>` and `MutableIterator<T>` (STDLIB-COL-TYPE-006).
    private func ensureSyntheticMutableListIteratorStub(
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner,
        kotlinCollectionsPkg: [InternedString]
    ) -> SymbolID {
        let mutableListIteratorName = interner.intern("MutableListIterator")
        let mutableListIteratorFQName = kotlinCollectionsPkg + [mutableListIteratorName]
        if let existing = symbols.lookup(fqName: mutableListIteratorFQName) {
            return existing
        }

        let listIteratorSymbol = ensureSyntheticListIteratorStub(
            symbols: symbols, types: types, interner: interner,
            kotlinCollectionsPkg: kotlinCollectionsPkg
        )
        let mutableIteratorSymbol = symbols.lookup(
            fqName: kotlinCollectionsPkg + [interner.intern("MutableIterator")]
        )

        let mutableListIteratorSymbol = symbols.define(
            kind: .interface,
            name: mutableListIteratorName,
            fqName: mutableListIteratorFQName,
            declSite: nil,
            visibility: .public,
            flags: [.synthetic]
        )

        let typeParamName = interner.intern("T")
        let typeParamFQName = mutableListIteratorFQName + [typeParamName]
        let typeParamSymbol = symbols.define(
            kind: .typeParameter,
            name: typeParamName,
            fqName: typeParamFQName,
            declSite: nil,
            visibility: .private,
            flags: []
        )
        let typeParamType = types.make(.typeParam(TypeParamType(
            symbol: typeParamSymbol,
            nullability: .nonNull
        )))
        types.setNominalTypeParameterSymbols([typeParamSymbol], for: mutableListIteratorSymbol)
        types.setNominalTypeParameterVariances([.invariant], for: mutableListIteratorSymbol)

        var directSupertypes = [listIteratorSymbol]
        if let mutableIteratorSymbol {
            directSupertypes.append(mutableIteratorSymbol)
        }
        symbols.setDirectSupertypes(directSupertypes, for: mutableListIteratorSymbol)
        types.setNominalDirectSupertypes(directSupertypes, for: mutableListIteratorSymbol)
        symbols.setSupertypeTypeArgs([.out(typeParamType)], for: mutableListIteratorSymbol, supertype: listIteratorSymbol)
        types.setNominalSupertypeTypeArgs([.out(typeParamType)], for: mutableListIteratorSymbol, supertype: listIteratorSymbol)
        if let mutableIteratorSymbol {
            symbols.setSupertypeTypeArgs([.out(typeParamType)], for: mutableListIteratorSymbol, supertype: mutableIteratorSymbol)
            types.setNominalSupertypeTypeArgs([.out(typeParamType)], for: mutableListIteratorSymbol, supertype: mutableIteratorSymbol)
        }

        let receiverType = types.make(.classType(ClassType(
            classSymbol: mutableListIteratorSymbol,
            args: [.invariant(typeParamType)],
            nullability: .nonNull
        )))

        func registerMutationMember(name: String) {
            let memberName = interner.intern(name)
            let memberFQName = mutableListIteratorFQName + [memberName]
            guard symbols.lookup(fqName: memberFQName) == nil else { return }
            let memberSymbol = symbols.define(
                kind: .function,
                name: memberName,
                fqName: memberFQName,
                declSite: nil,
                visibility: .public,
                flags: [.synthetic]
            )
            symbols.setParentSymbol(mutableListIteratorSymbol, for: memberSymbol)
            let valueName = interner.intern("element")
            let valueSymbol = symbols.define(
                kind: .valueParameter,
                name: valueName,
                fqName: memberFQName + [valueName],
                declSite: nil,
                visibility: .private,
                flags: [.synthetic]
            )
            symbols.setParentSymbol(memberSymbol, for: valueSymbol)
            symbols.setFunctionSignature(
                FunctionSignature(
                    receiverType: receiverType,
                    parameterTypes: [typeParamType],
                    returnType: types.unitType,
                    valueParameterSymbols: [valueSymbol],
                    valueParameterHasDefaultValues: [false],
                    valueParameterIsVararg: [false],
                    typeParameterSymbols: [typeParamSymbol],
                    classTypeParameterCount: 1
                ),
                for: memberSymbol
            )
        }

        func registerRemoveMember() {
            let memberName = interner.intern("remove")
            let memberFQName = mutableListIteratorFQName + [memberName]
            guard symbols.lookup(fqName: memberFQName) == nil else { return }
            let memberSymbol = symbols.define(
                kind: .function,
                name: memberName,
                fqName: memberFQName,
                declSite: nil,
                visibility: .public,
                flags: [.synthetic]
            )
            symbols.setParentSymbol(mutableListIteratorSymbol, for: memberSymbol)
            symbols.setFunctionSignature(
                FunctionSignature(
                    receiverType: receiverType,
                    parameterTypes: [],
                    returnType: types.unitType,
                    valueParameterSymbols: [],
                    valueParameterHasDefaultValues: [],
                    valueParameterIsVararg: [],
                    typeParameterSymbols: [typeParamSymbol],
                    classTypeParameterCount: 1
                ),
                for: memberSymbol
            )
        }

        registerMutationMember(name: "add")
        registerMutationMember(name: "set")
        registerRemoveMember()

        return mutableListIteratorSymbol
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

    /// Register `MutableList<E>.listIterator(): MutableListIterator<E>`.
    func registerMutableListIteratorMember(
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner,
        kotlinCollectionsPkg: [InternedString],
        mutableListFQName: [InternedString],
        mutableListInterfaceSymbol: SymbolID,
        mlTypeParamSymbol: SymbolID,
        mlTypeParamType: TypeID
    ) {
        let mutableListIteratorSymbol = ensureSyntheticMutableListIteratorStub(
            symbols: symbols, types: types, interner: interner,
            kotlinCollectionsPkg: kotlinCollectionsPkg
        )

        let memberName = interner.intern("listIterator")
        let memberFQName = mutableListFQName + [memberName]
        guard symbols.lookup(fqName: memberFQName) == nil else { return }

        let receiverType = types.make(.classType(ClassType(
            classSymbol: mutableListInterfaceSymbol,
            args: [.invariant(mlTypeParamType)],
            nullability: .nonNull
        )))
        let returnType = types.make(.classType(ClassType(
            classSymbol: mutableListIteratorSymbol,
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
        symbols.setExternalLinkName("kk_list_iterator", for: memberSymbol)
        symbols.setPropertyType(types.make(.functionType(FunctionType(
            params: [], returnType: returnType, isSuspend: false, nullability: .nonNull
        ))), for: memberSymbol)
        symbols.setFunctionSignature(
            FunctionSignature(
                receiverType: receiverType,
                parameterTypes: [],
                returnType: returnType,
                typeParameterSymbols: [mlTypeParamSymbol],
                classTypeParameterCount: 1
            ),
            for: memberSymbol
        )
    }

    /// STDLIB-183: List<T>.component1() ~ component5() for destructuring.
    func registerListComponentNMembers(
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
    func registerSetToSetMember(
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
    func registerSetToMutableSetMember(
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
            args: [.invariant(typeParamType)],
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
        mapInterfaceSymbol: SymbolID,
        listTypeParamSymbol: SymbolID,
        listTypeParamType: TypeID
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

        let associateToMemberName = interner.intern("associateTo")
        let associateToMemberFQName = listFQName + [associateToMemberName]
        guard symbols.lookup(fqName: associateToMemberFQName) == nil else { return }

        let associateToKeyTypeParamName = interner.intern("K")
        let associateToValueTypeParamName = interner.intern("V")
        let associateToKeyTypeParamSymbol = symbols.define(
            kind: .typeParameter,
            name: associateToKeyTypeParamName,
            fqName: associateToMemberFQName + [associateToKeyTypeParamName],
            declSite: nil,
            visibility: .private,
            flags: []
        )
        let associateToValueTypeParamSymbol = symbols.define(
            kind: .typeParameter,
            name: associateToValueTypeParamName,
            fqName: associateToMemberFQName + [associateToValueTypeParamName],
            declSite: nil,
            visibility: .private,
            flags: []
        )
        let associateToKeyType = types.make(.typeParam(TypeParamType(
            symbol: associateToKeyTypeParamSymbol, nullability: .nonNull
        )))
        let associateToValueType = types.make(.typeParam(TypeParamType(
            symbol: associateToValueTypeParamSymbol, nullability: .nonNull
        )))
        let associateToReceiverType = types.make(.classType(ClassType(
            classSymbol: listInterfaceSymbol,
            args: [.out(listTypeParamType)],
            nullability: .nonNull
        )))
        let associateToDestinationType = types.make(.classType(ClassType(
            classSymbol: mapInterfaceSymbol,
            args: [.out(associateToKeyType), .out(associateToValueType)],
            nullability: .nonNull
        )))
        let associateToTransformType = types.make(.functionType(FunctionType(
            params: [listTypeParamType],
            returnType: types.make(.classType(ClassType(
                classSymbol: pairSymbol,
                args: [.out(associateToKeyType), .out(associateToValueType)],
                nullability: .nonNull
            ))),
            isSuspend: false,
            nullability: .nonNull
        )))
        let associateToMemberSymbol = symbols.define(
            kind: .function,
            name: associateToMemberName,
            fqName: associateToMemberFQName,
            declSite: nil,
            visibility: .public,
            flags: [.synthetic, .operatorFunction]
        )
        symbols.setParentSymbol(listInterfaceSymbol, for: associateToMemberSymbol)
        symbols.setParentSymbol(associateToMemberSymbol, for: associateToKeyTypeParamSymbol)
        symbols.setParentSymbol(associateToMemberSymbol, for: associateToValueTypeParamSymbol)
        symbols.setExternalLinkName("kk_list_associateTo", for: associateToMemberSymbol)
        symbols.setFunctionSignature(
            FunctionSignature(
                receiverType: associateToReceiverType,
                parameterTypes: [associateToDestinationType, associateToTransformType],
                returnType: associateToDestinationType,
                typeParameterSymbols: [listTypeParamSymbol, associateToKeyTypeParamSymbol, associateToValueTypeParamSymbol],
                classTypeParameterCount: 1
            ),
            for: associateToMemberSymbol
        )

        // STDLIB-COL-DEST-004: associateByTo(destination, keySelector) -> M
        let associateByToMemberName = interner.intern("associateByTo")
        let associateByToMemberFQName = listFQName + [associateByToMemberName]
        if symbols.lookup(fqName: associateByToMemberFQName) == nil {
            let associateByToKeyTypeParamName = interner.intern("K")
            let associateByToKeyTypeParamSymbol = symbols.define(
                kind: .typeParameter,
                name: associateByToKeyTypeParamName,
                fqName: associateByToMemberFQName + [associateByToKeyTypeParamName],
                declSite: nil,
                visibility: .private,
                flags: []
            )
            let associateByToKeyType = types.make(.typeParam(TypeParamType(
                symbol: associateByToKeyTypeParamSymbol, nullability: .nonNull
            )))
            let associateByToReceiverType = types.make(.classType(ClassType(
                classSymbol: listInterfaceSymbol,
                args: [.out(listTypeParamType)],
                nullability: .nonNull
            )))
            let associateByToDestinationType = types.make(.classType(ClassType(
                classSymbol: mapInterfaceSymbol,
                args: [.out(associateByToKeyType), .out(listTypeParamType)],
                nullability: .nonNull
            )))
            let associateByToKeySelectorType = types.make(.functionType(FunctionType(
                params: [listTypeParamType],
                returnType: associateByToKeyType,
                isSuspend: false,
                nullability: .nonNull
            )))
            let associateByToMemberSymbol = symbols.define(
                kind: .function,
                name: associateByToMemberName,
                fqName: associateByToMemberFQName,
                declSite: nil,
                visibility: .public,
                flags: [.synthetic, .operatorFunction]
            )
            symbols.setParentSymbol(listInterfaceSymbol, for: associateByToMemberSymbol)
            symbols.setParentSymbol(associateByToMemberSymbol, for: associateByToKeyTypeParamSymbol)
            symbols.setExternalLinkName("kk_list_associateByTo", for: associateByToMemberSymbol)
            symbols.setFunctionSignature(
                FunctionSignature(
                    receiverType: associateByToReceiverType,
                    parameterTypes: [associateByToDestinationType, associateByToKeySelectorType],
                    returnType: associateByToDestinationType,
                    typeParameterSymbols: [listTypeParamSymbol, associateByToKeyTypeParamSymbol],
                    classTypeParameterCount: 1
                ),
                for: associateByToMemberSymbol
            )
        }

        // STDLIB-COL-DEST-004: associateWithTo(destination, valueSelector) -> M
        let associateWithToMemberName = interner.intern("associateWithTo")
        let associateWithToMemberFQName = listFQName + [associateWithToMemberName]
        if symbols.lookup(fqName: associateWithToMemberFQName) == nil {
            let associateWithToValueTypeParamName = interner.intern("V")
            let associateWithToValueTypeParamSymbol = symbols.define(
                kind: .typeParameter,
                name: associateWithToValueTypeParamName,
                fqName: associateWithToMemberFQName + [associateWithToValueTypeParamName],
                declSite: nil,
                visibility: .private,
                flags: []
            )
            let associateWithToValueType = types.make(.typeParam(TypeParamType(
                symbol: associateWithToValueTypeParamSymbol, nullability: .nonNull
            )))
            let associateWithToReceiverType = types.make(.classType(ClassType(
                classSymbol: listInterfaceSymbol,
                args: [.out(listTypeParamType)],
                nullability: .nonNull
            )))
            let associateWithToDestinationType = types.make(.classType(ClassType(
                classSymbol: mapInterfaceSymbol,
                args: [.out(listTypeParamType), .out(associateWithToValueType)],
                nullability: .nonNull
            )))
            let associateWithToValueSelectorType = types.make(.functionType(FunctionType(
                params: [listTypeParamType],
                returnType: associateWithToValueType,
                isSuspend: false,
                nullability: .nonNull
            )))
            let associateWithToMemberSymbol = symbols.define(
                kind: .function,
                name: associateWithToMemberName,
                fqName: associateWithToMemberFQName,
                declSite: nil,
                visibility: .public,
                flags: [.synthetic, .operatorFunction]
            )
            symbols.setParentSymbol(listInterfaceSymbol, for: associateWithToMemberSymbol)
            symbols.setParentSymbol(associateWithToMemberSymbol, for: associateWithToValueTypeParamSymbol)
            symbols.setExternalLinkName("kk_list_associateWithTo", for: associateWithToMemberSymbol)
            symbols.setFunctionSignature(
                FunctionSignature(
                    receiverType: associateWithToReceiverType,
                    parameterTypes: [associateWithToDestinationType, associateWithToValueSelectorType],
                    returnType: associateWithToDestinationType,
                    typeParameterSymbols: [listTypeParamSymbol, associateWithToValueTypeParamSymbol],
                    classTypeParameterCount: 1
                ),
                for: associateWithToMemberSymbol
            )
        }

        // STDLIB-COL-DEST-004: groupByTo(destination, keySelector) -> M
        let groupByToMemberName = interner.intern("groupByTo")
        let groupByToMemberFQName = listFQName + [groupByToMemberName]
        if symbols.lookup(fqName: groupByToMemberFQName) == nil {
            let groupByToKeyTypeParamName = interner.intern("K")
            let groupByToKeyTypeParamSymbol = symbols.define(
                kind: .typeParameter,
                name: groupByToKeyTypeParamName,
                fqName: groupByToMemberFQName + [groupByToKeyTypeParamName],
                declSite: nil,
                visibility: .private,
                flags: []
            )
            let groupByToKeyType = types.make(.typeParam(TypeParamType(
                symbol: groupByToKeyTypeParamSymbol, nullability: .nonNull
            )))
            let groupByToReceiverType = types.make(.classType(ClassType(
                classSymbol: listInterfaceSymbol,
                args: [.out(listTypeParamType)],
                nullability: .nonNull
            )))
            let groupByToDestinationType = types.make(.classType(ClassType(
                classSymbol: mapInterfaceSymbol,
                args: [.out(groupByToKeyType), .out(listTypeParamType)],
                nullability: .nonNull
            )))
            let groupByToKeySelectorType = types.make(.functionType(FunctionType(
                params: [listTypeParamType],
                returnType: groupByToKeyType,
                isSuspend: false,
                nullability: .nonNull
            )))
            let groupByToMemberSymbol = symbols.define(
                kind: .function,
                name: groupByToMemberName,
                fqName: groupByToMemberFQName,
                declSite: nil,
                visibility: .public,
                flags: [.synthetic, .operatorFunction]
            )
            symbols.setParentSymbol(listInterfaceSymbol, for: groupByToMemberSymbol)
            symbols.setParentSymbol(groupByToMemberSymbol, for: groupByToKeyTypeParamSymbol)
            symbols.setExternalLinkName("kk_list_groupByTo", for: groupByToMemberSymbol)
            symbols.setFunctionSignature(
                FunctionSignature(
                    receiverType: groupByToReceiverType,
                    parameterTypes: [groupByToDestinationType, groupByToKeySelectorType],
                    returnType: groupByToDestinationType,
                    typeParameterSymbols: [listTypeParamSymbol, groupByToKeyTypeParamSymbol],
                    classTypeParameterCount: 1
                ),
                for: groupByToMemberSymbol
            )
        }
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
        listTypeParamType: TypeID,
        collectionInterfaceSymbol: SymbolID
    ) {
        let receiverType = types.make(.classType(ClassType(
            classSymbol: listInterfaceSymbol,
            args: [.out(listTypeParamType)],
            nullability: .nonNull
        )))
        let listReturnType = receiverType
        if types.comparableInterfaceSymbol == nil {
            registerSyntheticComparableStub(symbols: symbols, types: types, interner: interner)
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

        // Register a synthetic member on List. Skips only when a symbol with the
        // same fully-qualified name and matching parameter list already exists
        // (overloads with distinct signatures are all registered).
        func registerMember(
            name: String,
            parameterTypes: [TypeID],
            externalLinkName: String,
            returnTypeOverride: TypeID? = nil,
            typeParameterUpperBoundsList: [[TypeID]]? = nil
        ) {
            let memberName = interner.intern(name)
            let memberFQName = listFQName + [memberName]
            let alreadySameSignature = symbols.lookupAll(fqName: memberFQName).contains { symbolID in
                guard let sig = symbols.functionSignature(for: symbolID) else { return false }
                return sig.parameterTypes == parameterTypes
            }
            guard !alreadySameSignature else { return }
            registerMemberOverload(
                memberName: memberName,
                memberFQName: memberFQName,
                parameterTypes: parameterTypes,
                externalLinkName: externalLinkName,
                returnTypeOverride: returnTypeOverride,
                typeParameterUpperBoundsList: typeParameterUpperBoundsList
            )
        }

        // Register a synthetic member overload on List, checking for
        // duplicate registrations by comparing parameter signatures.
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

        registerMember(name: "take", parameterTypes: [types.intType], externalLinkName: "kk_list_take")
        registerMember(name: "drop", parameterTypes: [types.intType], externalLinkName: "kk_list_drop")
        registerMember(name: "takeLast", parameterTypes: [types.intType], externalLinkName: "kk_list_takeLast")
        registerMember(name: "dropLast", parameterTypes: [types.intType], externalLinkName: "kk_list_dropLast")
        registerMember(name: "sum", parameterTypes: [], externalLinkName: "kk_list_sum", returnTypeOverride: types.intType)
        registerMember(name: "average", parameterTypes: [], externalLinkName: "kk_list_average", returnTypeOverride: types.doubleType)
        registerMember(name: "reversed", parameterTypes: [], externalLinkName: "kk_list_reversed")
        registerMember(name: "asReversed", parameterTypes: [], externalLinkName: "kk_list_as_reversed")
        registerMember(
            name: "sorted",
            parameterTypes: [],
            externalLinkName: "kk_list_sorted",
            typeParameterUpperBoundsList: [comparableElementBounds]
        )
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

        let destinationCollectionType = types.make(.classType(ClassType(
            classSymbol: collectionInterfaceSymbol,
            args: [.out(listTypeParamType)],
            nullability: .nonNull
        )))
        registerMemberOverload(
            memberName: interner.intern("filterTo"),
            memberFQName: listFQName + [interner.intern("filterTo")],
            parameterTypes: [
                destinationCollectionType,
                types.make(.functionType(FunctionType(
                    params: [listTypeParamType],
                    returnType: types.booleanType,
                    isSuspend: false,
                    nullability: .nonNull
                )))
            ],
            externalLinkName: "kk_list_filterTo",
            returnTypeOverride: destinationCollectionType
        )
        registerMemberOverload(
            memberName: interner.intern("filterNotTo"),
            memberFQName: listFQName + [interner.intern("filterNotTo")],
            parameterTypes: [
                destinationCollectionType,
                types.make(.functionType(FunctionType(
                    params: [listTypeParamType],
                    returnType: types.booleanType,
                    isSuspend: false,
                    nullability: .nonNull
                )))
            ],
            externalLinkName: "kk_list_filterNotTo",
            returnTypeOverride: destinationCollectionType
        )

        let mapToTypeParamName = interner.intern("R")
        let mapToTypeParamSymbol = symbols.define(
            kind: .typeParameter,
            name: mapToTypeParamName,
            fqName: listFQName + [interner.intern("mapTo"), mapToTypeParamName],
            declSite: nil,
            visibility: .private,
            flags: []
        )
        let mapToTypeParamType = types.make(.typeParam(TypeParamType(
            symbol: mapToTypeParamSymbol, nullability: .nonNull
        )))
        let mapToDestinationType = types.make(.classType(ClassType(
            classSymbol: collectionInterfaceSymbol,
            args: [.out(mapToTypeParamType)],
            nullability: .nonNull
        )))
        registerMemberOverload(
            memberName: interner.intern("mapTo"),
            memberFQName: listFQName + [interner.intern("mapTo")],
            parameterTypes: [
                mapToDestinationType,
                types.make(.functionType(FunctionType(
                    params: [listTypeParamType],
                    returnType: mapToTypeParamType,
                    isSuspend: false,
                    nullability: .nonNull
                )))
            ],
            externalLinkName: "kk_list_mapTo",
            returnTypeOverride: mapToDestinationType,
            typeParameterSymbols: [listTypeParamSymbol, mapToTypeParamSymbol]
        )

        let flatMapToTypeParamName = interner.intern("R")
        let flatMapToTypeParamSymbol = symbols.define(
            kind: .typeParameter,
            name: flatMapToTypeParamName,
            fqName: listFQName + [interner.intern("flatMapTo"), flatMapToTypeParamName],
            declSite: nil,
            visibility: .private,
            flags: []
        )
        let flatMapToTypeParamType = types.make(.typeParam(TypeParamType(
            symbol: flatMapToTypeParamSymbol, nullability: .nonNull
        )))
        let flatMapToDestinationType = types.make(.classType(ClassType(
            classSymbol: collectionInterfaceSymbol,
            args: [.out(flatMapToTypeParamType)],
            nullability: .nonNull
        )))
        let flatMapToLambdaReturnType = types.make(.classType(ClassType(
            classSymbol: collectionInterfaceSymbol,
            args: [.out(flatMapToTypeParamType)],
            nullability: .nonNull
        )))
        registerMemberOverload(
            memberName: interner.intern("flatMapTo"),
            memberFQName: listFQName + [interner.intern("flatMapTo")],
            parameterTypes: [
                flatMapToDestinationType,
                types.make(.functionType(FunctionType(
                    params: [listTypeParamType],
                    returnType: flatMapToLambdaReturnType,
                    isSuspend: false,
                    nullability: .nonNull
                )))
            ],
            externalLinkName: "kk_list_flatMapTo",
            returnTypeOverride: flatMapToDestinationType,
            typeParameterSymbols: [listTypeParamSymbol, flatMapToTypeParamSymbol]
        )

        let mapNotNullToTypeParamName = interner.intern("R")
        let mapNotNullToTypeParamSymbol = symbols.define(
            kind: .typeParameter,
            name: mapNotNullToTypeParamName,
            fqName: listFQName + [interner.intern("mapNotNullTo"), mapNotNullToTypeParamName],
            declSite: nil,
            visibility: .private,
            flags: []
        )
        let mapNotNullToTypeParamType = types.make(.typeParam(TypeParamType(
            symbol: mapNotNullToTypeParamSymbol, nullability: .nonNull
        )))
        let mapNotNullToDestinationType = types.make(.classType(ClassType(
            classSymbol: collectionInterfaceSymbol,
            args: [.out(mapNotNullToTypeParamType)],
            nullability: .nonNull
        )))
        registerMemberOverload(
            memberName: interner.intern("mapNotNullTo"),
            memberFQName: listFQName + [interner.intern("mapNotNullTo")],
            parameterTypes: [
                mapNotNullToDestinationType,
                types.make(.functionType(FunctionType(
                    params: [listTypeParamType],
                    returnType: types.nullableAnyType,
                    isSuspend: false,
                    nullability: .nonNull
                )))
            ],
            externalLinkName: "kk_list_mapNotNullTo",
            returnTypeOverride: mapNotNullToDestinationType,
            typeParameterSymbols: [listTypeParamSymbol, mapNotNullToTypeParamSymbol]
        )

        let mapIndexedToTypeParamName = interner.intern("R")
        let mapIndexedToTypeParamSymbol = symbols.define(
            kind: .typeParameter,
            name: mapIndexedToTypeParamName,
            fqName: listFQName + [interner.intern("mapIndexedTo"), mapIndexedToTypeParamName],
            declSite: nil,
            visibility: .private,
            flags: []
        )
        let mapIndexedToTypeParamType = types.make(.typeParam(TypeParamType(
            symbol: mapIndexedToTypeParamSymbol, nullability: .nonNull
        )))
        let mapIndexedToDestinationType = types.make(.classType(ClassType(
            classSymbol: collectionInterfaceSymbol,
            args: [.out(mapIndexedToTypeParamType)],
            nullability: .nonNull
        )))
        registerMemberOverload(
            memberName: interner.intern("mapIndexedTo"),
            memberFQName: listFQName + [interner.intern("mapIndexedTo")],
            parameterTypes: [
                mapIndexedToDestinationType,
                types.make(.functionType(FunctionType(
                    params: [types.intType, listTypeParamType],
                    returnType: mapIndexedToTypeParamType,
                    isSuspend: false,
                    nullability: .nonNull
                )))
            ],
            externalLinkName: "kk_list_mapIndexedTo",
            returnTypeOverride: mapIndexedToDestinationType,
            typeParameterSymbols: [listTypeParamSymbol, mapIndexedToTypeParamSymbol]
        )

        let flatMapIndexedToTypeParamName = interner.intern("R")
        let flatMapIndexedToTypeParamSymbol = symbols.define(
            kind: .typeParameter,
            name: flatMapIndexedToTypeParamName,
            fqName: listFQName + [interner.intern("flatMapIndexedTo"), flatMapIndexedToTypeParamName],
            declSite: nil,
            visibility: .private,
            flags: []
        )
        let flatMapIndexedToTypeParamType = types.make(.typeParam(TypeParamType(
            symbol: flatMapIndexedToTypeParamSymbol, nullability: .nonNull
        )))
        let flatMapIndexedToDestinationType = types.make(.classType(ClassType(
            classSymbol: collectionInterfaceSymbol,
            args: [.out(flatMapIndexedToTypeParamType)],
            nullability: .nonNull
        )))
        let flatMapIndexedToLambdaReturnType = types.make(.classType(ClassType(
            classSymbol: collectionInterfaceSymbol,
            args: [.out(flatMapIndexedToTypeParamType)],
            nullability: .nonNull
        )))
        registerMemberOverload(
            memberName: interner.intern("flatMapIndexedTo"),
            memberFQName: listFQName + [interner.intern("flatMapIndexedTo")],
            parameterTypes: [
                flatMapIndexedToDestinationType,
                types.make(.functionType(FunctionType(
                    params: [types.intType, listTypeParamType],
                    returnType: flatMapIndexedToLambdaReturnType,
                    isSuspend: false,
                    nullability: .nonNull
                )))
            ],
            externalLinkName: "kk_list_flatMapIndexedTo",
            returnTypeOverride: flatMapIndexedToDestinationType,
            typeParameterSymbols: [listTypeParamSymbol, flatMapIndexedToTypeParamSymbol]
        )

        let filterIsInstanceToTypeParamName = interner.intern("R")
        let filterIsInstanceToTypeParamSymbol = symbols.define(
            kind: .typeParameter,
            name: filterIsInstanceToTypeParamName,
            fqName: listFQName + [interner.intern("filterIsInstanceTo"), filterIsInstanceToTypeParamName],
            declSite: nil,
            visibility: .private,
            flags: [.reifiedTypeParameter]
        )
        let filterIsInstanceToTypeParamType = types.make(.typeParam(TypeParamType(
            symbol: filterIsInstanceToTypeParamSymbol, nullability: .nonNull
        )))
        let filterIsInstanceToDestinationType = types.make(.classType(ClassType(
            classSymbol: collectionInterfaceSymbol,
            args: [.out(filterIsInstanceToTypeParamType)],
            nullability: .nonNull
        )))
        registerMemberOverload(
            memberName: interner.intern("filterIsInstanceTo"),
            memberFQName: listFQName + [interner.intern("filterIsInstanceTo")],
            parameterTypes: [filterIsInstanceToDestinationType],
            externalLinkName: "kk_list_filterIsInstanceTo",
            returnTypeOverride: filterIsInstanceToDestinationType,
            typeParameterSymbols: [listTypeParamSymbol, filterIsInstanceToTypeParamSymbol],
            reifiedTypeParameterIndices: [1]
        )

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

        // STDLIB-COL-WIN-001: windowed(size, step, partialWindows, transform)
        // The transform overload erases R at the ABI level, so it returns List<Any>.
        do {
            let windowedTransformName = interner.intern("windowed")
            let windowedTransformFQName = listFQName + [windowedTransformName]
            let existingWindowedOverloads = symbols.lookupAll(fqName: windowedTransformFQName)
            let hasFourParamWindowed = existingWindowedOverloads.contains { symID in
                guard let sig = symbols.functionSignature(for: symID) else { return false }
                return sig.parameterTypes.count == 4
            }
            if !hasFourParamWindowed {
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
                let listOfAnyReturnType = types.make(.classType(ClassType(
                    classSymbol: listInterfaceSymbol,
                    args: [.out(types.anyType)],
                    nullability: .nonNull
                )))
                let memberSymbol = symbols.define(
                    kind: .function,
                    name: windowedTransformName,
                    fqName: windowedTransformFQName,
                    declSite: nil,
                    visibility: .public,
                    flags: [.synthetic, .inlineFunction]
                )
                symbols.setParentSymbol(listInterfaceSymbol, for: memberSymbol)
                symbols.setExternalLinkName("kk_list_windowed_transform", for: memberSymbol)
                symbols.setFunctionSignature(
                    FunctionSignature(
                        receiverType: receiverType,
                        parameterTypes: [types.intType, types.intType, types.booleanType, transformType],
                        returnType: listOfAnyReturnType,
                        typeParameterSymbols: [listTypeParamSymbol],
                        classTypeParameterCount: 1
                    ),
                    for: memberSymbol
                )
            }
        }
        registerMember(
            name: "sortedDescending",
            parameterTypes: [],
            externalLinkName: "kk_list_sortedDescending",
            typeParameterUpperBoundsList: [comparableElementBounds]
        )
        registerMember(name: "subList", parameterTypes: [types.intType, types.intType], externalLinkName: "kk_list_subList")

        // STDLIB-214: List.slice(indices: IntRange) and List.slice(indices: Iterable<Int>)
        // IntRange expressions are typed as intType at the ABI level, so the IntRange overload
        // is registered with parameterType=intType.  The Iterable<Int> overload uses List<out Int>.
        // resolveCollectionFallbackCallee distinguishes the two via isRangeExpr on the argument.
        do {
            let sliceName = interner.intern("slice")
            let sliceFQName = listFQName + [sliceName]
            let listOfIntType = types.make(.classType(ClassType(
                classSymbol: listInterfaceSymbol,
                args: [.out(types.intType)],
                nullability: .nonNull
            )))
            // IntRange overload: parameterType = intType
            let existingSlice = symbols.lookupAll(fqName: sliceFQName)
            let hasIntRangeSlice = existingSlice.contains { symID in
                guard let sig = symbols.functionSignature(for: symID) else { return false }
                return sig.parameterTypes == [types.intType] &&
                    symbols.externalLinkName(for: symID) == "kk_list_slice"
            }
            if !hasIntRangeSlice {
                let sym = symbols.define(
                    kind: .function, name: sliceName, fqName: sliceFQName,
                    declSite: nil, visibility: .public, flags: [.synthetic]
                )
                symbols.setParentSymbol(listInterfaceSymbol, for: sym)
                symbols.setExternalLinkName("kk_list_slice", for: sym)
                symbols.setFunctionSignature(
                    FunctionSignature(
                        receiverType: receiverType, parameterTypes: [types.intType],
                        returnType: listReturnType, typeParameterSymbols: [listTypeParamSymbol],
                        classTypeParameterCount: 1
                    ),
                    for: sym
                )
            }
            // Iterable<Int> overload: parameterType = List<out Int>
            let hasIterableSlice = existingSlice.contains { symID in
                guard let sig = symbols.functionSignature(for: symID) else { return false }
                return sig.parameterTypes == [listOfIntType]
            }
            if !hasIterableSlice {
                let sym = symbols.define(
                    kind: .function, name: sliceName, fqName: sliceFQName,
                    declSite: nil, visibility: .public, flags: [.synthetic]
                )
                symbols.setParentSymbol(listInterfaceSymbol, for: sym)
                symbols.setExternalLinkName("kk_list_slice_iterable", for: sym)
                symbols.setFunctionSignature(
                    FunctionSignature(
                        receiverType: receiverType, parameterTypes: [listOfIntType],
                        returnType: listReturnType, typeParameterSymbols: [listTypeParamSymbol],
                        classTypeParameterCount: 1
                    ),
                    for: sym
                )
            }
        }

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

    func registerListConversionMembers(
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
            mapInterfaceSymbol: mapInterfaceSymbol,
            listTypeParamSymbol: listTypeParamSymbol,
            listTypeParamType: listTypeParamType
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
        let kotlinPkg = [interner.intern("kotlin")]
        registerListToPrimitiveArrayMember(
            symbols: symbols, types: types, interner: interner,
            listInterfaceSymbol: listInterfaceSymbol,
            listTypeParamSymbol: listTypeParamSymbol,
            memberName: "toBooleanArray",
            arrayTypeName: "BooleanArray",
            arrayPackage: kotlinPkg,
            externalLinkName: "kk_list_toBooleanArray"
        )
        registerListToPrimitiveArrayMember(
            symbols: symbols, types: types, interner: interner,
            listInterfaceSymbol: listInterfaceSymbol,
            listTypeParamSymbol: listTypeParamSymbol,
            memberName: "toShortArray",
            arrayTypeName: "ShortArray",
            arrayPackage: kotlinPkg,
            externalLinkName: "kk_list_toShortArray"
        )
        registerListToPrimitiveArrayMember(
            symbols: symbols, types: types, interner: interner,
            listInterfaceSymbol: listInterfaceSymbol,
            listTypeParamSymbol: listTypeParamSymbol,
            memberName: "toDoubleArray",
            arrayTypeName: "DoubleArray",
            arrayPackage: kotlinPkg,
            externalLinkName: "kk_list_toDoubleArray"
        )
        registerListToPrimitiveArrayMember(
            symbols: symbols, types: types, interner: interner,
            listInterfaceSymbol: listInterfaceSymbol,
            listTypeParamSymbol: listTypeParamSymbol,
            memberName: "toIntArray",
            arrayTypeName: "IntArray",
            arrayPackage: kotlinPkg,
            externalLinkName: "kk_list_toIntArray"
        )
        registerListToPrimitiveArrayMember(
            symbols: symbols, types: types, interner: interner,
            listInterfaceSymbol: listInterfaceSymbol,
            listTypeParamSymbol: listTypeParamSymbol,
            memberName: "toLongArray",
            arrayTypeName: "LongArray",
            arrayPackage: kotlinPkg,
            externalLinkName: "kk_list_toLongArray"
        )
        registerListToPrimitiveArrayMember(
            symbols: symbols, types: types, interner: interner,
            listInterfaceSymbol: listInterfaceSymbol,
            listTypeParamSymbol: listTypeParamSymbol,
            memberName: "toByteArray",
            arrayTypeName: "ByteArray",
            arrayPackage: kotlinPkg,
            externalLinkName: "kk_list_toByteArray"
        )
        registerListToPrimitiveArrayMember(
            symbols: symbols, types: types, interner: interner,
            listInterfaceSymbol: listInterfaceSymbol,
            listTypeParamSymbol: listTypeParamSymbol,
            memberName: "toUByteArray",
            arrayTypeName: "UByteArray",
            arrayPackage: kotlinPkg,
            externalLinkName: "kk_list_toUByteArray"
        )
        registerListToPrimitiveArrayMember(
            symbols: symbols, types: types, interner: interner,
            listInterfaceSymbol: listInterfaceSymbol,
            listTypeParamSymbol: listTypeParamSymbol,
            memberName: "toUShortArray",
            arrayTypeName: "UShortArray",
            arrayPackage: kotlinPkg,
            externalLinkName: "kk_list_toUShortArray"
        )
        registerListToPrimitiveArrayMember(
            symbols: symbols, types: types, interner: interner,
            listInterfaceSymbol: listInterfaceSymbol,
            listTypeParamSymbol: listTypeParamSymbol,
            memberName: "toUIntArray",
            arrayTypeName: "UIntArray",
            arrayPackage: kotlinPkg,
            externalLinkName: "kk_list_toUIntArray"
        )
        registerListToPrimitiveArrayMember(
            symbols: symbols, types: types, interner: interner,
            listInterfaceSymbol: listInterfaceSymbol,
            listTypeParamSymbol: listTypeParamSymbol,
            memberName: "toULongArray",
            arrayTypeName: "ULongArray",
            arrayPackage: kotlinPkg,
            externalLinkName: "kk_list_toULongArray"
        )
    }

    /// Register a `List<E>.toXxxArray(): XxxArray` conversion member stub.
    ///
    /// Used for `toIntArray`, `toLongArray`, and `toByteArray` (STDLIB-LIST-PRIM-ARRAY).
    private func registerListToPrimitiveArrayMember(
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner,
        listInterfaceSymbol: SymbolID,
        listTypeParamSymbol: SymbolID,
        memberName: String,
        arrayTypeName: String,
        arrayPackage: [InternedString],
        externalLinkName: String
    ) {
        guard let listFQName = symbols.symbol(listInterfaceSymbol)?.fqName else { return }
        let internedMemberName = interner.intern(memberName)
        let memberFQName = listFQName + [internedMemberName]

        let listTypeParamType = types.make(.typeParam(TypeParamType(
            symbol: listTypeParamSymbol, nullability: .nonNull
        )))
        let receiverType = types.make(.classType(ClassType(
            classSymbol: listInterfaceSymbol,
            args: [.out(listTypeParamType)],
            nullability: .nonNull
        )))

        let arraySymbol = ensureClassSymbol(
            named: arrayTypeName,
            in: arrayPackage,
            symbols: symbols,
            interner: interner
        )
        
        // Ensure the primitive array has size property and toList() method
        let sizeName = interner.intern("size")
        let sizeFQName = arrayPackage + [interner.intern(arrayTypeName), sizeName]
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
            symbols.setPropertyType(types.intType, for: sizeSym)
            
            // Set external link name for size property
            let sizeLinkName: String = switch arrayTypeName {
            case "IntArray": "kk_intArray_size"
            case "LongArray": "kk_longArray_size"
            case "ByteArray": "kk_byteArray_size"
            case "ShortArray": "kk_shortArray_size"
            case "UIntArray": "kk_uIntArray_size"
            case "ULongArray": "kk_uLongArray_size"
            case "DoubleArray": "kk_doubleArray_size"
            case "FloatArray": "kk_floatArray_size"
            case "BooleanArray": "kk_booleanArray_size"
            case "CharArray": "kk_charArray_size"
            case "UByteArray": "kk_uByteArray_size"
            case "UShortArray": "kk_uShortArray_size"
            default: "kk_array_size"
            }
            symbols.setExternalLinkName(sizeLinkName, for: sizeSym)
        }
        
        // Also register toList() method for this primitive array
        let toListName = interner.intern("toList")
        let toListFQName = arrayPackage + [interner.intern(arrayTypeName), toListName]
        if symbols.lookup(fqName: toListFQName) == nil {
            let toListSym = symbols.define(
                kind: .function,
                name: toListName,
                fqName: toListFQName,
                declSite: nil,
                visibility: .public,
                flags: [.synthetic]
            )
            symbols.setParentSymbol(arraySymbol, for: toListSym)
            
            let externalLinkName: String = switch arrayTypeName {
            case "IntArray": "kk_intArray_toList"
            case "LongArray": "kk_longArray_toList"
            case "ByteArray": "kk_byteArray_toList"
            case "ShortArray": "kk_shortArray_toList"
            case "UIntArray": "kk_uIntArray_toList"
            case "ULongArray": "kk_uLongArray_toList"
            case "DoubleArray": "kk_doubleArray_toList"
            case "FloatArray": "kk_floatArray_toList"
            case "BooleanArray": "kk_booleanArray_toList"
            case "CharArray": "kk_charArray_toList"
            case "UByteArray": "kk_uByteArray_toList"
            case "UShortArray": "kk_uShortArray_toList"
            default: "kk_array_toList"
            }
            symbols.setExternalLinkName(externalLinkName, for: toListSym)
            
            // Get List interface for return type
            let listFQName = [interner.intern("kotlin"), interner.intern("collections"), interner.intern("List")]
            if let listSymbol = symbols.lookup(fqName: listFQName) {
                let elementType: TypeID = switch arrayTypeName {
                case "IntArray": types.intType
                case "LongArray": types.longType
                case "ByteArray": types.intType
                case "ShortArray": types.intType
                case "UIntArray": types.uintType
                case "ULongArray": types.ulongType
                case "DoubleArray": types.doubleType
                case "FloatArray": types.floatType
                case "BooleanArray": types.booleanType
                case "CharArray": types.charType
                case "UByteArray": types.ubyteType
                case "UShortArray": types.ushortType
                default: types.intType
                }
                
                let listReturnType = types.make(.classType(ClassType(
                    classSymbol: listSymbol,
                    args: [.invariant(elementType)],
                    nullability: .nonNull
                )))
                
                let arrayReceiverType = types.make(.classType(ClassType(
                    classSymbol: arraySymbol,
                    args: [],
                    nullability: .nonNull
                )))
                
                symbols.setFunctionSignature(
                    FunctionSignature(
                        receiverType: arrayReceiverType,
                        parameterTypes: [],
                        returnType: listReturnType,
                        isSuspend: false
                    ),
                    for: toListSym
                )
            }
        }
        
        guard symbols.lookup(fqName: memberFQName) == nil else { return }

        let returnType = types.make(.classType(ClassType(
            classSymbol: arraySymbol,
            args: [],
            nullability: .nonNull
        )))

        let memberSymbol = symbols.define(
            kind: .function,
            name: internedMemberName,
            fqName: memberFQName,
            declSite: nil,
            visibility: .public,
            flags: [.synthetic, .operatorFunction]
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

    /// Register `kotlin.collections.MutableList<E>` interface stub with `operator fun set(index: Int, element: E): E`.
}
