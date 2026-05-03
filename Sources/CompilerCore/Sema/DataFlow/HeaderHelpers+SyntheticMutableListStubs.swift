import Foundation

/// Synthetic stdlib stubs split from `HeaderHelpers+SyntheticComparableAndCollectionStubs.swift`:
/// MutableList<E> interface, mutation members, and the synthetic List extension function helper.
///
/// Split out to isolate merge conflicts between parallel stdlib PRs adding new
/// entries to this package.
extension DataFlowSemaPhase {

    func registerSyntheticMutableListStub(
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner,
        kotlinCollectionsPkg: [InternedString],
        listInterfaceSymbol: SymbolID,
        collectionInterfaceSymbol: SymbolID,
        mutableIterableInterfaceSymbol: SymbolID
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
        symbols.setDirectSupertypes([listInterfaceSymbol, mutableIterableInterfaceSymbol], for: mutableListInterfaceSymbol)
        types.setNominalDirectSupertypes([listInterfaceSymbol, mutableIterableInterfaceSymbol], for: mutableListInterfaceSymbol)
        symbols.setSupertypeTypeArgs([.out(mlTypeParamType)], for: mutableListInterfaceSymbol, supertype: listInterfaceSymbol)
        types.setNominalSupertypeTypeArgs([.out(mlTypeParamType)], for: mutableListInterfaceSymbol, supertype: listInterfaceSymbol)
        symbols.setSupertypeTypeArgs([.invariant(mlTypeParamType)], for: mutableListInterfaceSymbol, supertype: mutableIterableInterfaceSymbol)
        types.setNominalSupertypeTypeArgs([.invariant(mlTypeParamType)], for: mutableListInterfaceSymbol, supertype: mutableIterableInterfaceSymbol)

        registerMutableListIteratorMember(
            symbols: symbols, types: types, interner: interner,
            kotlinCollectionsPkg: kotlinCollectionsPkg,
            mutableListFQName: mutableListFQName,
            mutableListInterfaceSymbol: mutableListInterfaceSymbol,
            mlTypeParamSymbol: mlTypeParamSymbol,
            mlTypeParamType: mlTypeParamType
        )
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
        registerMutableListFillMember(
            symbols: symbols, types: types, interner: interner,
            mutableListFQName: mutableListFQName,
            mutableListInterfaceSymbol: mutableListInterfaceSymbol,
            mlTypeParamSymbol: mlTypeParamSymbol,
            mlTypeParamType: mlTypeParamType
        )
        registerMutableListReplaceAllMember(
            symbols: symbols, types: types, interner: interner,
            mutableListFQName: mutableListFQName,
            mutableListInterfaceSymbol: mutableListInterfaceSymbol,
            mlTypeParamSymbol: mlTypeParamSymbol,
            mlTypeParamType: mlTypeParamType
        )
        registerMutableListRemoveIfMember(
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
        registerMutableListSortWithMember(
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
        registerMutableListSortDescendingMember(
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

    private func registerMutableListFillMember(
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner,
        mutableListFQName: [InternedString],
        mutableListInterfaceSymbol: SymbolID,
        mlTypeParamSymbol: SymbolID,
        mlTypeParamType: TypeID
    ) {
        let memberName = interner.intern("fill")
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
        symbols.setExternalLinkName("kk_mutable_list_fill", for: memberSymbol)
        symbols.setFunctionSignature(
            FunctionSignature(
                receiverType: receiverType,
                parameterTypes: [mlTypeParamType],
                returnType: types.unitType,
                typeParameterSymbols: [mlTypeParamSymbol],
                classTypeParameterCount: 1
            ),
            for: memberSymbol
        )
    }

    private func registerMutableListReplaceAllMember(
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner,
        mutableListFQName: [InternedString],
        mutableListInterfaceSymbol: SymbolID,
        mlTypeParamSymbol: SymbolID,
        mlTypeParamType: TypeID
    ) {
        let memberName = interner.intern("replaceAll")
        let memberFQName = mutableListFQName + [memberName]
        guard symbols.lookup(fqName: memberFQName) == nil else { return }
        let receiverType = types.make(.classType(ClassType(
            classSymbol: mutableListInterfaceSymbol,
            args: [.invariant(mlTypeParamType)],
            nullability: .nonNull
        )))
        let operationType = types.make(.functionType(FunctionType(
            params: [mlTypeParamType],
            returnType: mlTypeParamType,
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
        symbols.setExternalLinkName("kk_mutable_list_replaceAll", for: memberSymbol)
        symbols.setFunctionSignature(
            FunctionSignature(
                receiverType: receiverType,
                parameterTypes: [operationType],
                returnType: types.unitType,
                canThrow: true,
                typeParameterSymbols: [mlTypeParamSymbol],
                classTypeParameterCount: 1
            ),
            for: memberSymbol
        )
    }

    private func registerMutableListRemoveIfMember(
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner,
        mutableListFQName: [InternedString],
        mutableListInterfaceSymbol: SymbolID,
        mlTypeParamSymbol: SymbolID,
        mlTypeParamType: TypeID
    ) {
        let memberName = interner.intern("removeIf")
        let memberFQName = mutableListFQName + [memberName]
        guard symbols.lookup(fqName: memberFQName) == nil else { return }
        let receiverType = types.make(.classType(ClassType(
            classSymbol: mutableListInterfaceSymbol,
            args: [.invariant(mlTypeParamType)],
            nullability: .nonNull
        )))
        let predicateType = types.make(.functionType(FunctionType(
            params: [mlTypeParamType],
            returnType: types.booleanType,
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
        symbols.setExternalLinkName("kk_mutable_list_removeIf", for: memberSymbol)
        symbols.setFunctionSignature(
            FunctionSignature(
                receiverType: receiverType,
                parameterTypes: [predicateType],
                returnType: types.booleanType,
                canThrow: true,
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

    private func registerMutableListSortWithMember(
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner,
        mutableListFQName: [InternedString],
        mutableListInterfaceSymbol: SymbolID,
        mlTypeParamSymbol: SymbolID,
        mlTypeParamType: TypeID
    ) {
        let memberName = interner.intern("sortWith")
        let memberFQName = mutableListFQName + [memberName]
        guard symbols.lookup(fqName: memberFQName) == nil else { return }
        let receiverType = types.make(.classType(ClassType(
            classSymbol: mutableListInterfaceSymbol,
            args: [.invariant(mlTypeParamType)],
            nullability: .nonNull
        )))
        let comparatorType = types.make(.functionType(FunctionType(
            params: [mlTypeParamType, mlTypeParamType],
            returnType: types.intType,
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
        symbols.setExternalLinkName("kk_mutable_list_sortWith", for: memberSymbol)
        symbols.setFunctionSignature(
            FunctionSignature(
                receiverType: receiverType,
                parameterTypes: [comparatorType],
                returnType: types.unitType,
                typeParameterSymbols: [mlTypeParamSymbol],
                typeParameterUpperBoundsList: [[]],
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

    private func registerMutableListSortDescendingMember(
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner,
        mutableListFQName: [InternedString],
        mutableListInterfaceSymbol: SymbolID,
        mlTypeParamSymbol: SymbolID,
        mlTypeParamType: TypeID
    ) {
        let memberName = interner.intern("sortDescending")
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
            flags: [.synthetic, .inlineFunction]
        )
        symbols.setParentSymbol(mutableListInterfaceSymbol, for: memberSymbol)
        symbols.setExternalLinkName("kk_mutable_list_sortDescending", for: memberSymbol)
        symbols.setFunctionSignature(
            FunctionSignature(
                receiverType: receiverType,
                parameterTypes: [],
                returnType: types.unitType,
                typeParameterSymbols: [mlTypeParamSymbol],
                typeParameterUpperBoundsList: [[]],
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

    /// Helper function for registering List extension functions.
    func registerSyntheticListExtensionFunction(
        named name: String,
        externalLinkName: String,
        receiverType: TypeID,
        parameters: [(name: String, type: TypeID, hasDefault: Bool, isVararg: Bool)],
        returnType: TypeID,
        typeParameterSymbols: [SymbolID] = [],
        flags: SymbolFlags = [.synthetic],
        packageFQName: [InternedString],
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner
    ) {
        let functionName = interner.intern(name)
        let functionFQName = packageFQName + [functionName]
        if let existing = symbols.lookupAll(fqName: functionFQName).first(where: { symbolID in
            guard let existingSignature = symbols.functionSignature(for: symbolID) else {
                return false
            }
            return existingSignature.receiverType == receiverType
                && existingSignature.parameterTypes == parameters.map { $0.type }
        }) {
            symbols.setExternalLinkName(externalLinkName, for: existing)
            return
        }

        let functionSymbol = symbols.define(
            kind: .function,
            name: functionName,
            fqName: functionFQName,
            declSite: nil,
            visibility: .public,
            flags: flags
        )
        if let packageSymbol = symbols.lookup(fqName: packageFQName) {
            symbols.setParentSymbol(packageSymbol, for: functionSymbol)
        }
        symbols.setExternalLinkName(externalLinkName, for: functionSymbol)

        var parameterTypes: [TypeID] = []
        var parameterSymbols: [SymbolID] = []
        var parameterDefaults: [Bool] = []
        var parameterVarargs: [Bool] = []
        parameterTypes.reserveCapacity(parameters.count)
        parameterSymbols.reserveCapacity(parameters.count)
        parameterDefaults.reserveCapacity(parameters.count)
        parameterVarargs.reserveCapacity(parameters.count)

        for parameter in parameters {
            let parameterName = interner.intern(parameter.name)
            let parameterSymbol = symbols.define(
                kind: .valueParameter,
                name: parameterName,
                fqName: functionFQName + [parameterName],
                declSite: nil,
                visibility: .private,
                flags: [.synthetic]
            )
            symbols.setParentSymbol(functionSymbol, for: parameterSymbol)
            parameterTypes.append(parameter.type)
            parameterSymbols.append(parameterSymbol)
            parameterDefaults.append(parameter.hasDefault)
            parameterVarargs.append(parameter.isVararg)
        }

        symbols.setFunctionSignature(
            FunctionSignature(
                receiverType: receiverType,
                parameterTypes: parameterTypes,
                returnType: returnType,
                isSuspend: false,
                valueParameterSymbols: parameterSymbols,
                valueParameterHasDefaultValues: parameterDefaults,
                valueParameterIsVararg: parameterVarargs,
                typeParameterSymbols: typeParameterSymbols
            ),
            for: functionSymbol
        )

        symbols.setPropertyType(types.make(.functionType(FunctionType(
            params: parameterTypes,
            returnType: returnType,
            isSuspend: false,
            nullability: .nonNull
        ))), for: functionSymbol)
    }
}
