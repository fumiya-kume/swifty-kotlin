
/// Synthetic stdlib stubs split from the KSP-697 collection residual registry:
/// MutableList<E> interface, mutation members, and the synthetic List extension function helper.
///
/// Split out to isolate merge conflicts between parallel stdlib PRs adding new
/// entries to this package.
extension DataFlowSemaPhase {

    private func hasMutableListOverload(
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner,
        fqName: [InternedString],
        mutableListInterfaceSymbol: SymbolID,
        parameterCount: Int,
        parameterClassSymbol: SymbolID? = nil,
        mlTypeParamType: TypeID
    ) -> Bool {
        if parameterClassSymbol == nil,
           let contextTypes = BundledSyntheticStubRegistration.types,
           let memberName = fqName.last,
           BundledSyntheticStubRegistration.shouldSkipRegistration(
               declaredOwnerFQName: Array(fqName.dropLast()),
               receiverType: types.make(.classType(ClassType(
                   classSymbol: mutableListInterfaceSymbol,
                   args: [.invariant(mlTypeParamType)],
                   nullability: .nonNull
               ))),
               name: memberName,
               arity: parameterCount,
               symbols: symbols,
               types: contextTypes,
               interner: interner
           )
        {
            return true
        }
        return symbols.lookupAll(fqName: fqName).contains { symbolID in
            guard let signature = symbols.functionSignature(for: symbolID),
                  let receiverType = signature.receiverType,
                  case let .classType(receiverClass) = types.kind(of: types.makeNonNullable(receiverType)),
                  receiverClass.classSymbol == mutableListInterfaceSymbol,
                  signature.parameterTypes.count == parameterCount
            else {
                return false
            }
            guard let parameterClassSymbol else {
                return true
            }
            guard let parameterType = signature.parameterTypes.first,
                  case let .classType(parameterClass) = types.kind(of: types.makeNonNullable(parameterType))
            else {
                return false
            }
            return parameterClass.classSymbol == parameterClassSymbol
        }
    }

    func registerSyntheticMutableListStub(
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner,
        kotlinCollectionsPkg: [InternedString],
        listInterfaceSymbol: SymbolID,
        collectionInterfaceSymbol: SymbolID,
        mutableCollectionInterfaceSymbol: SymbolID,
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
        symbols.setDirectSupertypes(
            [listInterfaceSymbol, mutableCollectionInterfaceSymbol, mutableIterableInterfaceSymbol],
            for: mutableListInterfaceSymbol
        )
        types.setNominalDirectSupertypes(
            [listInterfaceSymbol, mutableCollectionInterfaceSymbol, mutableIterableInterfaceSymbol],
            for: mutableListInterfaceSymbol
        )
        symbols.setSupertypeTypeArgs([.out(mlTypeParamType)], for: mutableListInterfaceSymbol, supertype: listInterfaceSymbol)
        types.setNominalSupertypeTypeArgs([.out(mlTypeParamType)], for: mutableListInterfaceSymbol, supertype: listInterfaceSymbol)
        symbols.setSupertypeTypeArgs([.invariant(mlTypeParamType)], for: mutableListInterfaceSymbol, supertype: mutableCollectionInterfaceSymbol)
        types.setNominalSupertypeTypeArgs([.invariant(mlTypeParamType)], for: mutableListInterfaceSymbol, supertype: mutableCollectionInterfaceSymbol)
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
        registerMutableListIteratorAtIndexMember(
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
        registerMutableListRemoveFirstMember(
            symbols: symbols, types: types, interner: interner,
            mutableListFQName: mutableListFQName,
            mutableListInterfaceSymbol: mutableListInterfaceSymbol,
            mlTypeParamSymbol: mlTypeParamSymbol,
            mlTypeParamType: mlTypeParamType
        )
        registerMutableListRemoveFirstOrNullMember(
            symbols: symbols, types: types, interner: interner,
            mutableListFQName: mutableListFQName,
            mutableListInterfaceSymbol: mutableListInterfaceSymbol,
            mlTypeParamSymbol: mlTypeParamSymbol,
            mlTypeParamType: mlTypeParamType
        )
        registerMutableListRemoveLastMember(
            symbols: symbols, types: types, interner: interner,
            mutableListFQName: mutableListFQName,
            mutableListInterfaceSymbol: mutableListInterfaceSymbol,
            mlTypeParamSymbol: mlTypeParamSymbol,
            mlTypeParamType: mlTypeParamType
        )
        registerMutableListRemoveLastOrNullMember(
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
        registerMutableListAddAllAtIndexMember(
            symbols: symbols, types: types, interner: interner,
            mutableListFQName: mutableListFQName,
            mutableListInterfaceSymbol: mutableListInterfaceSymbol,
            collectionInterfaceSymbol: collectionInterfaceSymbol,
            mlTypeParamSymbol: mlTypeParamSymbol,
            mlTypeParamType: mlTypeParamType
        )
        registerMutableListPlusAssignMembers(
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
        registerMutableListMinusAssignElementMember(
            symbols: symbols, types: types, interner: interner,
            mutableListFQName: mutableListFQName,
            mutableListInterfaceSymbol: mutableListInterfaceSymbol,
            mlTypeParamSymbol: mlTypeParamSymbol,
            mlTypeParamType: mlTypeParamType
        )
        registerMutableListMinusAssignCollectionMember(
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
        _ = registerSyntheticAbstractMutableListStub(
            symbols: symbols,
            types: types,
            interner: interner,
            kotlinCollectionsPkg: kotlinCollectionsPkg,
            listInterfaceSymbol: listInterfaceSymbol,
            mutableListInterfaceSymbol: mutableListInterfaceSymbol
        )
    }

    /// Restore the shared MutableIterable residual edge after a bundled
    /// MutableList source declaration is bound. The source declaration owns
    /// List/MutableCollection, while the compiler shell still owns the
    /// residual iterator/mutation surface and its direct compatibility edge.
    func patchSourceBackedMutableListSupertypes(
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner
    ) {
        let collectionsPackage = [interner.intern("kotlin"), interner.intern("collections")]
        let mutableListName = interner.intern("MutableList")
        let mutableIterableName = interner.intern("MutableIterable")
        guard let mutableListSymbol = symbols.lookup(fqName: collectionsPackage + [mutableListName]),
              let mutableListInfo = symbols.symbol(mutableListSymbol),
              !mutableListInfo.flags.contains(.synthetic),
              let mutableIterableSymbol = symbols.lookup(fqName: collectionsPackage + [mutableIterableName]),
              let typeParameter = types.nominalTypeParameterSymbols(for: mutableListSymbol).first
        else {
            return
        }

        let directSupertypes = symbols.directSupertypes(for: mutableListSymbol)
        guard !directSupertypes.contains(mutableIterableSymbol) else {
            return
        }
        let patchedSupertypes = Array(Set(directSupertypes + [mutableIterableSymbol]))
            .sorted(by: { $0.rawValue < $1.rawValue })
        symbols.setDirectSupertypes(patchedSupertypes, for: mutableListSymbol)
        types.setNominalDirectSupertypes(patchedSupertypes, for: mutableListSymbol)

        let typeParameterType = types.make(.typeParam(TypeParamType(
            symbol: typeParameter,
            nullability: .nonNull
        )))
        let mutableIterableTypeArgs: [TypeArg] = [.invariant(typeParameterType)]
        symbols.setSupertypeTypeArgs(
            mutableIterableTypeArgs,
            for: mutableListSymbol,
            supertype: mutableIterableSymbol
        )
        types.setNominalSupertypeTypeArgs(
            mutableIterableTypeArgs,
            for: mutableListSymbol,
            supertype: mutableIterableSymbol
        )
    }

    /// Register `kotlin.collections.AbstractMutableList<E>` surface (STDLIB-COL-ABSTRACT-006).
    func registerSyntheticAbstractMutableListStub(
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner,
        kotlinCollectionsPkg: [InternedString],
        listInterfaceSymbol: SymbolID,
        mutableListInterfaceSymbol: SymbolID
    ) -> SymbolID {
        let abstractMutableListName = interner.intern("AbstractMutableList")
        let abstractMutableListFQName = kotlinCollectionsPkg + [abstractMutableListName]
        let abstractMutableListSymbol: SymbolID = if let existing = symbols.lookup(fqName: abstractMutableListFQName) {
            existing
        } else {
            symbols.define(
                kind: .class,
                name: abstractMutableListName,
                fqName: abstractMutableListFQName,
                declSite: nil,
                visibility: .public,
                flags: [.synthetic, .abstractType]
            )
        }

        let typeParamName = interner.intern("E")
        let typeParamFQName = abstractMutableListFQName + [typeParamName]
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
        types.setNominalTypeParameterSymbols([typeParamSymbol], for: abstractMutableListSymbol)
        types.setNominalTypeParameterVariances([.invariant], for: abstractMutableListSymbol)

        let abstractMutableListType = types.make(.classType(ClassType(
            classSymbol: abstractMutableListSymbol,
            args: [.invariant(typeParamType)],
            nullability: .nonNull
        )))
        symbols.setPropertyType(abstractMutableListType, for: abstractMutableListSymbol)

        let abstractListSymbol = symbols.lookup(
            fqName: kotlinCollectionsPkg + [interner.intern("AbstractList")]
        )
        let readonlySupertype = abstractListSymbol ?? listInterfaceSymbol
        symbols.setDirectSupertypes([readonlySupertype, mutableListInterfaceSymbol], for: abstractMutableListSymbol)
        types.setNominalDirectSupertypes([readonlySupertype, mutableListInterfaceSymbol], for: abstractMutableListSymbol)
        symbols.setSupertypeTypeArgs([.out(typeParamType)], for: abstractMutableListSymbol, supertype: readonlySupertype)
        types.setNominalSupertypeTypeArgs([.out(typeParamType)], for: abstractMutableListSymbol, supertype: readonlySupertype)
        symbols.setSupertypeTypeArgs([.invariant(typeParamType)], for: abstractMutableListSymbol, supertype: mutableListInterfaceSymbol)
        types.setNominalSupertypeTypeArgs(
            [.invariant(typeParamType)],
            for: abstractMutableListSymbol,
            supertype: mutableListInterfaceSymbol
        )

        let initName = interner.intern("<init>")
        let initFQName = abstractMutableListFQName + [initName]
        if symbols.lookup(fqName: initFQName) == nil {
            let initSymbol = symbols.define(
                kind: .constructor,
                name: initName,
                fqName: initFQName,
                declSite: nil,
                visibility: .protected,
                flags: [.synthetic]
            )
            symbols.setParentSymbol(abstractMutableListSymbol, for: initSymbol)
            symbols.setFunctionSignature(
                FunctionSignature(
                    receiverType: nil,
                    parameterTypes: [],
                    returnType: abstractMutableListType,
                    valueParameterSymbols: [],
                    valueParameterHasDefaultValues: [],
                    valueParameterIsVararg: [],
                    typeParameterSymbols: [typeParamSymbol],
                    classTypeParameterCount: 1
                ),
                for: initSymbol
            )
        }

        return abstractMutableListSymbol
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
        symbols.setExternalLinkName("__kk_mutable_list_set", for: mlSetSymbol)
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
        // Use signature-aware guard: a kklib import may have created a no-signature ghost symbol
        // with the same FQ name. Only skip if a properly-configured add(E) overload already exists.
        guard symbols.lookupAll(fqName: memberFQName).first(where: { symbolID in
            guard let sig = symbols.functionSignature(for: symbolID) else { return false }
            return sig.parameterTypes == [mlTypeParamType] && sig.returnType == types.booleanType
        }) == nil else { return }
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
        symbols.setExternalLinkName("__kk_mutable_list_add", for: memberSymbol)
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
        symbols.setExternalLinkName("__kk_mutable_list_add_at", for: memberSymbol)
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
        symbols.setExternalLinkName("__kk_mutable_list_removeAt", for: memberSymbol)
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

    /// Register `fun removeFirst(): E` on MutableList (STDLIB-COL-MUT-003).
    private func registerMutableListRemoveFirstMember(
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner,
        mutableListFQName: [InternedString],
        mutableListInterfaceSymbol: SymbolID,
        mlTypeParamSymbol: SymbolID,
        mlTypeParamType: TypeID
    ) {
        let memberName = interner.intern("removeFirst")
        let memberFQName = mutableListFQName + [memberName]
        guard !hasMutableListOverload(
            symbols: symbols,
            types: types,
            interner: interner,
            fqName: memberFQName,
            mutableListInterfaceSymbol: mutableListInterfaceSymbol,
            parameterCount: 0,
            mlTypeParamType: mlTypeParamType
        ) else { return }
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
        symbols.setExternalLinkName("__kk_mutable_list_removeFirst", for: memberSymbol)
        symbols.setFunctionSignature(
            FunctionSignature(
                receiverType: receiverType,
                parameterTypes: [],
                returnType: mlTypeParamType,
                typeParameterSymbols: [mlTypeParamSymbol],
                classTypeParameterCount: 1
            ),
            for: memberSymbol
        )
    }

    /// Register `fun removeFirstOrNull(): E?` on MutableList (STDLIB-COL-MUT-001).
    private func registerMutableListRemoveFirstOrNullMember(
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner,
        mutableListFQName: [InternedString],
        mutableListInterfaceSymbol: SymbolID,
        mlTypeParamSymbol: SymbolID,
        mlTypeParamType: TypeID
    ) {
        let memberName = interner.intern("removeFirstOrNull")
        let memberFQName = mutableListFQName + [memberName]
        guard !hasMutableListOverload(
            symbols: symbols,
            types: types,
            interner: interner,
            fqName: memberFQName,
            mutableListInterfaceSymbol: mutableListInterfaceSymbol,
            parameterCount: 0,
            mlTypeParamType: mlTypeParamType
        ) else { return }
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
        symbols.setExternalLinkName("__kk_mutable_list_removeFirstOrNull", for: memberSymbol)
        symbols.setFunctionSignature(
            FunctionSignature(
                receiverType: receiverType,
                parameterTypes: [],
                returnType: types.makeNullable(mlTypeParamType),
                typeParameterSymbols: [mlTypeParamSymbol],
                classTypeParameterCount: 1
            ),
            for: memberSymbol
        )
    }

    /// Register `fun removeLast(): E` on MutableList (STDLIB-COL-MUT-004).
    private func registerMutableListRemoveLastMember(
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner,
        mutableListFQName: [InternedString],
        mutableListInterfaceSymbol: SymbolID,
        mlTypeParamSymbol: SymbolID,
        mlTypeParamType: TypeID
    ) {
        let memberName = interner.intern("removeLast")
        let memberFQName = mutableListFQName + [memberName]
        guard !hasMutableListOverload(
            symbols: symbols,
            types: types,
            interner: interner,
            fqName: memberFQName,
            mutableListInterfaceSymbol: mutableListInterfaceSymbol,
            parameterCount: 0,
            mlTypeParamType: mlTypeParamType
        ) else { return }
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
        symbols.setExternalLinkName("__kk_mutable_list_removeLast", for: memberSymbol)
        symbols.setFunctionSignature(
            FunctionSignature(
                receiverType: receiverType,
                parameterTypes: [],
                returnType: mlTypeParamType,
                typeParameterSymbols: [mlTypeParamSymbol],
                classTypeParameterCount: 1
            ),
            for: memberSymbol
        )
    }

    /// Register `fun removeLastOrNull(): E?` on MutableList (STDLIB-COL-MUT-002).
    private func registerMutableListRemoveLastOrNullMember(
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner,
        mutableListFQName: [InternedString],
        mutableListInterfaceSymbol: SymbolID,
        mlTypeParamSymbol: SymbolID,
        mlTypeParamType: TypeID
    ) {
        let memberName = interner.intern("removeLastOrNull")
        let memberFQName = mutableListFQName + [memberName]
        guard !hasMutableListOverload(
            symbols: symbols,
            types: types,
            interner: interner,
            fqName: memberFQName,
            mutableListInterfaceSymbol: mutableListInterfaceSymbol,
            parameterCount: 0,
            mlTypeParamType: mlTypeParamType
        ) else { return }
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
        symbols.setExternalLinkName("__kk_mutable_list_removeLastOrNull", for: memberSymbol)
        symbols.setFunctionSignature(
            FunctionSignature(
                receiverType: receiverType,
                parameterTypes: [],
                returnType: types.makeNullable(mlTypeParamType),
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
        symbols.setExternalLinkName("__kk_mutable_list_clear", for: memberSymbol)
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
        guard !hasMutableListOverload(
            symbols: symbols,
            types: types,
            interner: interner,
            fqName: memberFQName,
            mutableListInterfaceSymbol: mutableListInterfaceSymbol,
            parameterCount: 0,
            mlTypeParamType: mlTypeParamType
        ) else { return }
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
        symbols.setExternalLinkName("__kk_mutable_list_shuffle", for: memberSymbol)
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
        guard !hasMutableListOverload(
            symbols: symbols,
            types: types,
            interner: interner,
            fqName: memberFQName,
            mutableListInterfaceSymbol: mutableListInterfaceSymbol,
            parameterCount: 0,
            mlTypeParamType: mlTypeParamType
        ) else { return }
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
        symbols.setExternalLinkName("__kk_mutable_list_reverse", for: memberSymbol)
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
        guard !hasMutableListOverload(
            symbols: symbols,
            types: types,
            interner: interner,
            fqName: memberFQName,
            mutableListInterfaceSymbol: mutableListInterfaceSymbol,
            parameterCount: 1,
            parameterClassSymbol: collectionInterfaceSymbol,
            mlTypeParamType: mlTypeParamType
        ) else { return }
        let memberSymbol = symbols.define(
            kind: .function,
            name: memberName,
            fqName: memberFQName,
            declSite: nil,
            visibility: .public,
            flags: [.synthetic]
        )
        symbols.setParentSymbol(mutableListInterfaceSymbol, for: memberSymbol)
        symbols.setExternalLinkName("__kk_mutable_list_retainAll", for: memberSymbol)
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
        let receiverType = types.make(.classType(ClassType(
            classSymbol: mutableListInterfaceSymbol,
            args: [.invariant(mlTypeParamType)],
            nullability: .nonNull
        )))
        if BundledSyntheticStubRegistration.shouldSkipRegistration(
            declaredOwnerFQName: mutableListFQName,
            receiverType: receiverType,
            name: memberName,
            arity: 0,
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
            flags: [.synthetic, .operatorFunction]
        )
        symbols.setParentSymbol(mutableListInterfaceSymbol, for: memberSymbol)
        symbols.setExternalLinkName("__kk_mutable_list_sort", for: memberSymbol)
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
        let receiverType = types.make(.classType(ClassType(
            classSymbol: mutableListInterfaceSymbol,
            args: [.invariant(mlTypeParamType)],
            nullability: .nonNull
        )))
        if BundledSyntheticStubRegistration.shouldSkipRegistration(
            declaredOwnerFQName: mutableListFQName,
            receiverType: receiverType,
            name: memberName,
            arity: 1,
            symbols: symbols,
            types: types,
            interner: interner
        ) { return }
        guard symbols.lookup(fqName: memberFQName) == nil else { return }
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
        symbols.setExternalLinkName("__kk_mutable_list_sortWith", for: memberSymbol)
        symbols.setFunctionSignature(
            FunctionSignature(
                receiverType: receiverType,
                parameterTypes: [comparatorType],
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
        let receiverType = types.make(.classType(ClassType(
            classSymbol: mutableListInterfaceSymbol,
            args: [.invariant(mlTypeParamType)],
            nullability: .nonNull
        )))
        if BundledSyntheticStubRegistration.shouldSkipRegistration(
            declaredOwnerFQName: mutableListFQName,
            receiverType: receiverType,
            name: memberName,
            arity: 1,
            symbols: symbols,
            types: types,
            interner: interner
        ) { return }
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
        symbols.setExternalLinkName("__kk_mutable_list_sortBy", for: memberSymbol)
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
        let receiverType = types.make(.classType(ClassType(
            classSymbol: mutableListInterfaceSymbol,
            args: [.invariant(mlTypeParamType)],
            nullability: .nonNull
        )))
        if BundledSyntheticStubRegistration.shouldSkipRegistration(
            declaredOwnerFQName: mutableListFQName,
            receiverType: receiverType,
            name: memberName,
            arity: 1,
            symbols: symbols,
            types: types,
            interner: interner
        ) { return }
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
        symbols.setExternalLinkName("__kk_mutable_list_sortByDescending", for: memberSymbol)
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
        let receiverType = types.make(.classType(ClassType(
            classSymbol: mutableListInterfaceSymbol,
            args: [.invariant(mlTypeParamType)],
            nullability: .nonNull
        )))
        if BundledSyntheticStubRegistration.shouldSkipRegistration(
            declaredOwnerFQName: mutableListFQName,
            receiverType: receiverType,
            name: memberName,
            arity: 0,
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
        symbols.setParentSymbol(mutableListInterfaceSymbol, for: memberSymbol)
        symbols.setExternalLinkName("__kk_mutable_list_sortDescending", for: memberSymbol)
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
        symbols.setExternalLinkName("__kk_mutable_list_addAll", for: memberSymbol)
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

    /// Register `MutableList<E>.addAll(index: Int, elements: Collection<E>): Boolean`
    /// (bulk insert-at-index, distinct overload from the append-only `addAll` above).
    private func registerMutableListAddAllAtIndexMember(
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
        let paramType = types.make(.classType(ClassType(
            classSymbol: collectionInterfaceSymbol,
            args: [.out(mlTypeParamType)],
            nullability: .nonNull
        )))
        guard symbols.lookupAll(fqName: memberFQName).first(where: { symbolID in
            symbols.functionSignature(for: symbolID)?.parameterTypes == [types.intType, paramType]
        }) == nil else { return }
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
        symbols.setExternalLinkName("__kk_mutable_list_addAll_at", for: memberSymbol)
        symbols.setFunctionSignature(
            FunctionSignature(
                receiverType: receiverType,
                parameterTypes: [types.intType, paramType],
                returnType: types.booleanType,
                typeParameterSymbols: [mlTypeParamSymbol],
                classTypeParameterCount: 1
            ),
            for: memberSymbol
        )
    }

    private func registerMutableListPlusAssignMembers(
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner,
        mutableListFQName: [InternedString],
        mutableListInterfaceSymbol: SymbolID,
        collectionInterfaceSymbol: SymbolID,
        mlTypeParamSymbol: SymbolID,
        mlTypeParamType: TypeID
    ) {
        let memberName = interner.intern("plusAssign")
        let memberFQName = mutableListFQName + [memberName]
        let receiverType = types.make(.classType(ClassType(
            classSymbol: mutableListInterfaceSymbol,
            args: [.invariant(mlTypeParamType)],
            nullability: .nonNull
        )))
        let collectionType = types.make(.classType(ClassType(
            classSymbol: collectionInterfaceSymbol,
            args: [.out(mlTypeParamType)],
            nullability: .nonNull
        )))
        let overloads: [(params: [TypeID], external: String)] = [
            ([mlTypeParamType], "__kk_mutable_list_add"),
            ([collectionType], "__kk_mutable_list_addAll"),
        ]

        for overload in overloads {
            guard symbols.lookupAll(fqName: memberFQName).first(where: { symbolID in
                guard let signature = symbols.functionSignature(for: symbolID) else { return false }
                return signature.parameterTypes == overload.params &&
                    signature.returnType == types.unitType
            }) == nil else {
                continue
            }

            let memberSymbol = symbols.define(
                kind: .function,
                name: memberName,
                fqName: memberFQName,
                declSite: nil,
                visibility: .public,
                flags: [.synthetic, .operatorFunction]
            )
            symbols.setParentSymbol(mutableListInterfaceSymbol, for: memberSymbol)
            symbols.setExternalLinkName(overload.external, for: memberSymbol)
            symbols.setFunctionSignature(
                FunctionSignature(
                    receiverType: receiverType,
                    parameterTypes: overload.params,
                    returnType: types.unitType,
                    typeParameterSymbols: [mlTypeParamSymbol],
                    classTypeParameterCount: 1
                ),
                for: memberSymbol
            )
        }
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
        guard !hasMutableListOverload(
            symbols: symbols,
            types: types,
            interner: interner,
            fqName: memberFQName,
            mutableListInterfaceSymbol: mutableListInterfaceSymbol,
            parameterCount: 1,
            parameterClassSymbol: collectionInterfaceSymbol,
            mlTypeParamType: mlTypeParamType
        ) else { return }
        let memberSymbol = symbols.define(
            kind: .function,
            name: memberName,
            fqName: memberFQName,
            declSite: nil,
            visibility: .public,
            flags: [.synthetic, .operatorFunction]
        )
        symbols.setParentSymbol(mutableListInterfaceSymbol, for: memberSymbol)
        symbols.setExternalLinkName("__kk_mutable_list_removeAll", for: memberSymbol)
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

    private func registerMutableListMinusAssignElementMember(
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner,
        mutableListFQName: [InternedString],
        mutableListInterfaceSymbol: SymbolID,
        mlTypeParamSymbol: SymbolID,
        mlTypeParamType: TypeID
    ) {
        let memberName = interner.intern("minusAssign")
        let memberFQName = mutableListFQName + [memberName]
        guard symbols.lookupAll(fqName: memberFQName).first(where: { symbolID in
            symbols.externalLinkName(for: symbolID) == "__kk_mutable_list_remove"
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
            flags: [.synthetic, .operatorFunction]
        )
        symbols.setParentSymbol(mutableListInterfaceSymbol, for: memberSymbol)
        symbols.setExternalLinkName("__kk_mutable_list_remove", for: memberSymbol)
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

    private func registerMutableListMinusAssignCollectionMember(
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner,
        mutableListFQName: [InternedString],
        mutableListInterfaceSymbol: SymbolID,
        collectionInterfaceSymbol: SymbolID,
        mlTypeParamSymbol: SymbolID,
        mlTypeParamType: TypeID
    ) {
        let memberName = interner.intern("minusAssign")
        let memberFQName = mutableListFQName + [memberName]
        guard symbols.lookupAll(fqName: memberFQName).first(where: { symbolID in
            symbols.externalLinkName(for: symbolID) == "__kk_mutable_list_removeAll"
        }) == nil else {
            return
        }
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
        symbols.setExternalLinkName("__kk_mutable_list_removeAll", for: memberSymbol)
        symbols.setFunctionSignature(
            FunctionSignature(
                receiverType: receiverType,
                parameterTypes: [paramType],
                returnType: types.unitType,
                typeParameterSymbols: [mlTypeParamSymbol],
                classTypeParameterCount: 1
            ),
            for: memberSymbol
        )
    }

}
