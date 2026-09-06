import RuntimeABI

// KSP-697: List shell registration remains only as a compatibility fallback;
// the bundled nominal declaration is now Kotlin source-backed.

/// Synthetic stdlib residuals retained after the KSP-697 nominal shell migration:
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
        collectionInterfaceSymbol: SymbolID,
        bundledIndex: BundledDeclarationIndex = .empty,
        skipStats: SyntheticStubSkipStatsCollector? = nil
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
            collectionInterfaceSymbol: collectionInterfaceSymbol,
            bundledIndex: bundledIndex,
            skipStats: skipStats
        )
        registerListAggregateMembers(
            symbols: symbols, types: types, interner: interner,
            listFQName: listFQName,
            listInterfaceSymbol: listInterfaceSymbol,
            listTypeParamSymbol: listTypeParamSymbol,
            listTypeParamType: listTypeParamType,
            bundledIndex: bundledIndex,
            skipStats: skipStats
        )
        registerListIteratorMember(
            symbols: symbols, types: types, interner: interner,
            kotlinCollectionsPkg: kotlinCollectionsPkg,
            listFQName: listFQName,
            listInterfaceSymbol: listInterfaceSymbol,
            listTypeParamSymbol: listTypeParamSymbol,
            listTypeParamType: listTypeParamType
        )
        registerListIteratorAtIndexMember(
            symbols: symbols, types: types, interner: interner,
            kotlinCollectionsPkg: kotlinCollectionsPkg,
            listFQName: listFQName,
            listInterfaceSymbol: listInterfaceSymbol,
            listTypeParamSymbol: listTypeParamSymbol,
            listTypeParamType: listTypeParamType
        )
        return listInterfaceSymbol
    }

    /// Register `kotlin.collections.AbstractList<E>` surface (STDLIB-COL-ABSTRACT-003).
    func registerSyntheticAbstractListStub(
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner,
        kotlinCollectionsPkg: [InternedString],
        abstractCollectionSymbol: SymbolID,
        listInterfaceSymbol: SymbolID
    ) -> SymbolID {
        let abstractListName = interner.intern("AbstractList")
        let abstractListFQName = kotlinCollectionsPkg + [abstractListName]
        let abstractListSymbol: SymbolID = if let existing = symbols.lookup(fqName: abstractListFQName) {
            existing
        } else {
            symbols.define(
                kind: .class,
                name: abstractListName,
                fqName: abstractListFQName,
                declSite: nil,
                visibility: .public,
                flags: [.synthetic, .abstractType]
            )
        }

        let typeParamName = interner.intern("E")
        let typeParamFQName = abstractListFQName + [typeParamName]
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
        types.setNominalTypeParameterSymbols([typeParamSymbol], for: abstractListSymbol)
        types.setNominalTypeParameterVariances([.out], for: abstractListSymbol)

        let abstractListType = types.make(.classType(ClassType(
            classSymbol: abstractListSymbol,
            args: [.out(typeParamType)],
            nullability: .nonNull
        )))
        symbols.setPropertyType(abstractListType, for: abstractListSymbol)

        let directSupertypes = [abstractCollectionSymbol, listInterfaceSymbol]
        symbols.setDirectSupertypes(directSupertypes, for: abstractListSymbol)
        types.setNominalDirectSupertypes(directSupertypes, for: abstractListSymbol)
        symbols.setSupertypeTypeArgs([.out(typeParamType)], for: abstractListSymbol, supertype: abstractCollectionSymbol)
        types.setNominalSupertypeTypeArgs([.out(typeParamType)], for: abstractListSymbol, supertype: abstractCollectionSymbol)
        symbols.setSupertypeTypeArgs([.out(typeParamType)], for: abstractListSymbol, supertype: listInterfaceSymbol)
        types.setNominalSupertypeTypeArgs([.out(typeParamType)], for: abstractListSymbol, supertype: listInterfaceSymbol)

        let initName = interner.intern("<init>")
        let initFQName = abstractListFQName + [initName]
        if symbols.lookup(fqName: initFQName) == nil {
            let initSymbol = symbols.define(
                kind: .constructor,
                name: initName,
                fqName: initFQName,
                declSite: nil,
                visibility: .protected,
                flags: [.synthetic]
            )
            symbols.setParentSymbol(abstractListSymbol, for: initSymbol)
            symbols.setFunctionSignature(
                FunctionSignature(
                    receiverType: nil,
                    parameterTypes: [],
                    returnType: abstractListType,
                    valueParameterSymbols: [],
                    valueParameterHasDefaultValues: [],
                    valueParameterIsVararg: [],
                    typeParameterSymbols: [typeParamSymbol],
                    classTypeParameterCount: 1
                ),
                for: initSymbol
            )
        }

        return abstractListSymbol
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
        symbols.setExternalLinkName("__kk_list_get", for: listGetSymbol)
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

    private func ensureSyntheticListIteratorStub(
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner,
        kotlinCollectionsPkg: [InternedString],
        bundledIndex: BundledDeclarationIndex? = nil
    ) -> SymbolID {
        let listIteratorName = interner.intern("ListIterator")
        let listIteratorFQName = kotlinCollectionsPkg + [listIteratorName]
        let activeBundledIndex = bundledIndex ?? BundledSyntheticStubRegistration.bundledIndex
        // STDLIB-SHARED-014: ListIterator may have been imported as a synthetic
        // nominal anchor. In that case the interface exists but its members do
        // not, so continue with the existing symbol and (re)define members.
        var listIteratorSymbol: SymbolID
        if let existing = symbols.lookup(fqName: listIteratorFQName) {
            listIteratorSymbol = existing
        } else {
            listIteratorSymbol = symbols.define(
                kind: .interface,
                name: listIteratorName,
                fqName: listIteratorFQName,
                declSite: nil,
                visibility: .public,
                flags: [.synthetic]
            )
        }

        // Look up the parent Iterator<T> symbol.
        let iteratorName = interner.intern("Iterator")
        let iteratorFQName = kotlinCollectionsPkg + [iteratorName]
        let iteratorSymbol = symbols.lookup(fqName: iteratorFQName)

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
        if symbols.lookup(fqName: hasPreviousFQName) == nil,
           !activeBundledIndex.contains(owner: listIteratorFQName, name: hasPreviousName, arity: 0)
        {
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
        }

        // previous(): T
        let previousName = interner.intern("previous")
        let previousFQName = listIteratorFQName + [previousName]
        if symbols.lookup(fqName: previousFQName) == nil,
           !activeBundledIndex.contains(owner: listIteratorFQName, name: previousName, arity: 0)
        {
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
        }

        // nextIndex(): Int
        let nextIndexName = interner.intern("nextIndex")
        let nextIndexFQName = listIteratorFQName + [nextIndexName]
        if symbols.lookup(fqName: nextIndexFQName) == nil,
           !activeBundledIndex.contains(owner: listIteratorFQName, name: nextIndexName, arity: 0)
        {
            let nextIndexSym = symbols.define(
                kind: .function, name: nextIndexName, fqName: nextIndexFQName,
                declSite: nil, visibility: .public, flags: [.synthetic]
            )
            symbols.setParentSymbol(listIteratorSymbol, for: nextIndexSym)
            symbols.setPropertyType(types.make(.functionType(FunctionType(
                params: [], returnType: types.intType, isSuspend: false, nullability: .nonNull
            ))), for: nextIndexSym)
            symbols.setExternalLinkName("kk_list_iterator_nextIndex", for: nextIndexSym)
            symbols.setFunctionSignature(
                FunctionSignature(
                    receiverType: listIteratorReceiverType,
                    parameterTypes: [],
                    returnType: types.intType,
                    typeParameterSymbols: [tpSymbol],
                    classTypeParameterCount: 1
                ),
                for: nextIndexSym
            )
        }

        // previousIndex(): Int
        let previousIndexName = interner.intern("previousIndex")
        let previousIndexFQName = listIteratorFQName + [previousIndexName]
        if symbols.lookup(fqName: previousIndexFQName) == nil,
           !activeBundledIndex.contains(owner: listIteratorFQName, name: previousIndexName, arity: 0)
        {
            let previousIndexSym = symbols.define(
                kind: .function, name: previousIndexName, fqName: previousIndexFQName,
                declSite: nil, visibility: .public, flags: [.synthetic]
            )
            symbols.setParentSymbol(listIteratorSymbol, for: previousIndexSym)
            symbols.setPropertyType(types.make(.functionType(FunctionType(
                params: [], returnType: types.intType, isSuspend: false, nullability: .nonNull
            ))), for: previousIndexSym)
            symbols.setExternalLinkName("kk_list_iterator_previousIndex", for: previousIndexSym)
            symbols.setFunctionSignature(
                FunctionSignature(
                    receiverType: listIteratorReceiverType,
                    parameterTypes: [],
                    returnType: types.intType,
                    typeParameterSymbols: [tpSymbol],
                    classTypeParameterCount: 1
                ),
                for: previousIndexSym
            )
        }

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
        // STDLIB-SHARED-014: MutableListIterator may have been imported as a
        // synthetic nominal anchor with missing members.
        var mutableListIteratorSymbol: SymbolID
        if let existing = symbols.lookup(fqName: mutableListIteratorFQName) {
            mutableListIteratorSymbol = existing
        } else {
            mutableListIteratorSymbol = symbols.define(
                kind: .interface,
                name: mutableListIteratorName,
                fqName: mutableListIteratorFQName,
                declSite: nil,
                visibility: .public,
                flags: [.synthetic]
            )
        }

        let listIteratorSymbol = ensureSyntheticListIteratorStub(
            symbols: symbols, types: types, interner: interner,
            kotlinCollectionsPkg: kotlinCollectionsPkg
        )
        let mutableIteratorSymbol = symbols.lookup(
            fqName: kotlinCollectionsPkg + [interner.intern("MutableIterator")]
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
            kotlinCollectionsPkg: kotlinCollectionsPkg,
            bundledIndex: BundledSyntheticStubRegistration.bundledIndex
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

    /// Register `List<E>.listIterator(index: Int): ListIterator<E>`.
    private func registerListIteratorAtIndexMember(
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
        guard symbols.lookupAll(fqName: memberFQName).first(where: { symbolID in
            symbols.functionSignature(for: symbolID)?.parameterTypes == [types.intType]
        }) == nil else { return }

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
        symbols.setExternalLinkName("kk_list_iterator_at", for: memberSymbol)
        symbols.setFunctionSignature(
            FunctionSignature(
                receiverType: listReceiverType,
                parameterTypes: [types.intType],
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

    /// Register `MutableList<E>.listIterator(index: Int): MutableListIterator<E>`.
    func registerMutableListIteratorAtIndexMember(
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
        guard symbols.lookupAll(fqName: memberFQName).first(where: { symbolID in
            symbols.functionSignature(for: symbolID)?.parameterTypes == [types.intType]
        }) == nil else { return }

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
        symbols.setExternalLinkName("kk_list_iterator_at", for: memberSymbol)
        symbols.setFunctionSignature(
            FunctionSignature(
                receiverType: receiverType,
                parameterTypes: [types.intType],
                returnType: returnType,
                typeParameterSymbols: [mlTypeParamSymbol],
                classTypeParameterCount: 1
            ),
            for: memberSymbol
        )
    }

    /// Register the List-specific contains/isEmpty surface.
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

    /// STDLIB-510: Register `List<T>.intersect(other)`, `.union(other)`, `.subtract(other)` returning `Set<T>`.
    /// Kotlin stdlib declares the parameter as `Iterable<T>`.
    func registerListSetOperationMembers(
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
            ("intersect", "intersect"),
            ("union", "union"),
            ("subtract", "subtract"),
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

    func registerListToMapMember(
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

    }

    /// Register `List<E>.asSequence(): Sequence<E>` member stub (STDLIB-471).
    ///
    /// Note: `Array<E>.asSequence()` does not need a separate Sema stub because
    /// array member calls are resolved through the collection member-call
    /// fallback path (`CallTypeChecker+MemberCallFallbacks`), and the lowering
    /// pass routes to `kk_array_asSequence` via `arrayExprIDs` tracking.
    func registerListAsSequenceMember(
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner,
        listInterfaceSymbol: SymbolID,
        listTypeParamSymbol: SymbolID,
        listTypeParamType: TypeID,
        bundledIndex: BundledDeclarationIndex = .empty
    ) {
        guard let listFQName = symbols.symbol(listInterfaceSymbol)?.fqName else { return }
        let memberName = interner.intern("asSequence")
        let memberFQName = listFQName + [memberName]
        guard symbols.lookup(fqName: memberFQName) == nil else { return }
        // KSP-441〜447: Iterable.asSequence / List.asSequence source 化時は合成スタブを登録しない。
        let iterableFQName = Array(listFQName.dropLast()) + [interner.intern("Iterable")]
        guard !bundledIndex.contains(owner: listFQName, name: memberName, arity: 0)
            && !bundledIndex.contains(owner: iterableFQName, name: memberName, arity: 0)
        else { return }
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

}
