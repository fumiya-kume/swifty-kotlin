import Foundation

/// Synthetic stdlib stubs split from `HeaderHelpers+SyntheticComparableAndCollectionStubs.swift`:
/// Set<E> and MutableSet<E> interfaces with their member helpers.
///
/// Split out to isolate merge conflicts between parallel stdlib PRs adding new
/// entries to this package.
extension DataFlowSemaPhase {

    func registerSyntheticSetStub(
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

        // Set.minOrNull / Set.maxOrNull with T : Comparable<T> bound
        do {
            let nullableElementType = types.makeNullable(typeParamType)
            if types.comparableInterfaceSymbol == nil {
                registerSyntheticComparableStub(symbols: symbols, types: types, interner: interner)
            }
            let comparableElementBounds: [TypeID] = if let comparableSymbol = types.comparableInterfaceSymbol {
                [types.make(.classType(ClassType(
                    classSymbol: comparableSymbol,
                    args: [.invariant(typeParamType)],
                    nullability: .nonNull
                )))]
            } else {
                []
            }
            let setReceiverType = types.make(.classType(ClassType(
                classSymbol: setInterfaceSymbol,
                args: [.out(typeParamType)],
                nullability: .nonNull
            )))
            func registerSetComparableMember(name: String, externalLinkName: String) {
                let memberName = interner.intern(name)
                let memberFQName = setFQName + [memberName]
                guard symbols.lookup(fqName: memberFQName) == nil else { return }
                let memberSymbol = symbols.define(
                    kind: .function,
                    name: memberName,
                    fqName: memberFQName,
                    declSite: nil,
                    visibility: .public,
                    flags: [.synthetic]
                )
                symbols.setParentSymbol(setInterfaceSymbol, for: memberSymbol)
                symbols.setExternalLinkName(externalLinkName, for: memberSymbol)
                symbols.setFunctionSignature(
                    FunctionSignature(
                        receiverType: setReceiverType,
                        parameterTypes: [],
                        returnType: nullableElementType,
                        typeParameterSymbols: [typeParamSymbol],
                        typeParameterUpperBoundsList: [comparableElementBounds],
                        classTypeParameterCount: 1
                    ),
                    for: memberSymbol
                )
            }
            registerSetComparableMember(name: "maxOrNull", externalLinkName: "kk_set_maxOrNull")
            registerSetComparableMember(name: "minOrNull", externalLinkName: "kk_set_minOrNull")
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

    func registerSyntheticMutableSetStub(
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner,
        kotlinCollectionsPkg: [InternedString],
        setInterfaceSymbol: SymbolID,
        collectionInterfaceSymbol: SymbolID,
        mutableIterableInterfaceSymbol: SymbolID
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
        types.setNominalTypeParameterSymbols([typeParamSymbol], for: mutableSetInterfaceSymbol)
        types.setNominalTypeParameterVariances([.invariant], for: mutableSetInterfaceSymbol)
        symbols.setDirectSupertypes([setInterfaceSymbol, mutableIterableInterfaceSymbol], for: mutableSetInterfaceSymbol)
        types.setNominalDirectSupertypes([setInterfaceSymbol, mutableIterableInterfaceSymbol], for: mutableSetInterfaceSymbol)
        symbols.setSupertypeTypeArgs([.out(typeParamType)], for: mutableSetInterfaceSymbol, supertype: setInterfaceSymbol)
        types.setNominalSupertypeTypeArgs([.out(typeParamType)], for: mutableSetInterfaceSymbol, supertype: setInterfaceSymbol)
        symbols.setSupertypeTypeArgs([.invariant(typeParamType)], for: mutableSetInterfaceSymbol, supertype: mutableIterableInterfaceSymbol)
        types.setNominalSupertypeTypeArgs([.invariant(typeParamType)], for: mutableSetInterfaceSymbol, supertype: mutableIterableInterfaceSymbol)

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
        registerMutableSetPlusAssignMembers(
            symbols: symbols, types: types, interner: interner,
            mutableSetFQName: mutableSetFQName,
            mutableSetInterfaceSymbol: mutableSetInterfaceSymbol,
            collectionInterfaceSymbol: collectionInterfaceSymbol,
            typeParamSymbol: typeParamSymbol,
            typeParamType: typeParamType
        )
        registerMutableSetRemoveAllMember(
            symbols: symbols, types: types, interner: interner,
            mutableSetFQName: mutableSetFQName,
            mutableSetInterfaceSymbol: mutableSetInterfaceSymbol,
            collectionInterfaceSymbol: collectionInterfaceSymbol,
            typeParamSymbol: typeParamSymbol,
            typeParamType: typeParamType
        )
        registerMutableSetMinusAssignElementMember(
            symbols: symbols, types: types, interner: interner,
            mutableSetFQName: mutableSetFQName,
            mutableSetInterfaceSymbol: mutableSetInterfaceSymbol,
            typeParamSymbol: typeParamSymbol,
            typeParamType: typeParamType
        )
        registerMutableSetMinusAssignCollectionMember(
            symbols: symbols, types: types, interner: interner,
            mutableSetFQName: mutableSetFQName,
            mutableSetInterfaceSymbol: mutableSetInterfaceSymbol,
            collectionInterfaceSymbol: collectionInterfaceSymbol,
            typeParamSymbol: typeParamSymbol,
            typeParamType: typeParamType
        )
        registerMutableSetRetainAllMember(
            symbols: symbols, types: types, interner: interner,
            mutableSetFQName: mutableSetFQName,
            mutableSetInterfaceSymbol: mutableSetInterfaceSymbol,
            collectionInterfaceSymbol: collectionInterfaceSymbol,
            typeParamSymbol: typeParamSymbol,
            typeParamType: typeParamType
        )
        _ = registerSyntheticAbstractMutableSetStub(
            symbols: symbols,
            types: types,
            interner: interner,
            kotlinCollectionsPkg: kotlinCollectionsPkg,
            setInterfaceSymbol: setInterfaceSymbol,
            mutableSetInterfaceSymbol: mutableSetInterfaceSymbol
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

    /// Register `kotlin.collections.AbstractMutableSet<E>` surface (STDLIB-COL-ABSTRACT-008).
    func registerSyntheticAbstractMutableSetStub(
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner,
        kotlinCollectionsPkg: [InternedString],
        setInterfaceSymbol: SymbolID,
        mutableSetInterfaceSymbol: SymbolID
    ) -> SymbolID {
        let abstractMutableSetName = interner.intern("AbstractMutableSet")
        let abstractMutableSetFQName = kotlinCollectionsPkg + [abstractMutableSetName]
        let abstractMutableSetSymbol: SymbolID = if let existing = symbols.lookup(fqName: abstractMutableSetFQName) {
            existing
        } else {
            symbols.define(
                kind: .class,
                name: abstractMutableSetName,
                fqName: abstractMutableSetFQName,
                declSite: nil,
                visibility: .public,
                flags: [.synthetic, .abstractType]
            )
        }

        let typeParamName = interner.intern("E")
        let typeParamFQName = abstractMutableSetFQName + [typeParamName]
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
        types.setNominalTypeParameterSymbols([typeParamSymbol], for: abstractMutableSetSymbol)
        types.setNominalTypeParameterVariances([.invariant], for: abstractMutableSetSymbol)

        let abstractMutableSetType = types.make(.classType(ClassType(
            classSymbol: abstractMutableSetSymbol,
            args: [.invariant(typeParamType)],
            nullability: .nonNull
        )))
        symbols.setPropertyType(abstractMutableSetType, for: abstractMutableSetSymbol)

        let abstractSetSymbol = symbols.lookup(
            fqName: kotlinCollectionsPkg + [interner.intern("AbstractSet")]
        )
        let readonlySupertype = abstractSetSymbol ?? setInterfaceSymbol
        symbols.setDirectSupertypes([readonlySupertype, mutableSetInterfaceSymbol], for: abstractMutableSetSymbol)
        types.setNominalDirectSupertypes([readonlySupertype, mutableSetInterfaceSymbol], for: abstractMutableSetSymbol)
        symbols.setSupertypeTypeArgs([.out(typeParamType)], for: abstractMutableSetSymbol, supertype: readonlySupertype)
        types.setNominalSupertypeTypeArgs([.out(typeParamType)], for: abstractMutableSetSymbol, supertype: readonlySupertype)
        symbols.setSupertypeTypeArgs([.invariant(typeParamType)], for: abstractMutableSetSymbol, supertype: mutableSetInterfaceSymbol)
        types.setNominalSupertypeTypeArgs(
            [.invariant(typeParamType)],
            for: abstractMutableSetSymbol,
            supertype: mutableSetInterfaceSymbol
        )

        let initName = interner.intern("<init>")
        let initFQName = abstractMutableSetFQName + [initName]
        if symbols.lookup(fqName: initFQName) == nil {
            let initSymbol = symbols.define(
                kind: .constructor,
                name: initName,
                fqName: initFQName,
                declSite: nil,
                visibility: .protected,
                flags: [.synthetic]
            )
            symbols.setParentSymbol(abstractMutableSetSymbol, for: initSymbol)
            symbols.setFunctionSignature(
                FunctionSignature(
                    receiverType: nil,
                    parameterTypes: [],
                    returnType: abstractMutableSetType,
                    valueParameterSymbols: [],
                    valueParameterHasDefaultValues: [],
                    valueParameterIsVararg: [],
                    typeParameterSymbols: [typeParamSymbol],
                    classTypeParameterCount: 1
                ),
                for: initSymbol
            )
        }

        return abstractMutableSetSymbol
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

    private func registerMutableSetPlusAssignMembers(
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner,
        mutableSetFQName: [InternedString],
        mutableSetInterfaceSymbol: SymbolID,
        collectionInterfaceSymbol: SymbolID,
        typeParamSymbol: SymbolID,
        typeParamType: TypeID
    ) {
        let memberName = interner.intern("plusAssign")
        let memberFQName = mutableSetFQName + [memberName]
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
        let overloads: [(params: [TypeID], external: String)] = [
            ([typeParamType], "kk_mutable_set_add"),
            ([collectionType], "kk_mutable_set_addAll"),
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
            symbols.setParentSymbol(mutableSetInterfaceSymbol, for: memberSymbol)
            symbols.setExternalLinkName(overload.external, for: memberSymbol)
            symbols.setFunctionSignature(
                FunctionSignature(
                    receiverType: receiverType,
                    parameterTypes: overload.params,
                    returnType: types.unitType,
                    typeParameterSymbols: [typeParamSymbol],
                    classTypeParameterCount: 1
                ),
                for: memberSymbol
            )
        }
    }

    private func registerMutableSetRemoveAllMember(
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner,
        mutableSetFQName: [InternedString],
        mutableSetInterfaceSymbol: SymbolID,
        collectionInterfaceSymbol: SymbolID,
        typeParamSymbol: SymbolID,
        typeParamType: TypeID
    ) {
        let memberName = interner.intern("removeAll")
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
        symbols.setExternalLinkName("kk_mutable_set_removeAll", for: memberSymbol)
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

    private func registerMutableSetMinusAssignElementMember(
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner,
        mutableSetFQName: [InternedString],
        mutableSetInterfaceSymbol: SymbolID,
        typeParamSymbol: SymbolID,
        typeParamType: TypeID
    ) {
        let memberName = interner.intern("minusAssign")
        let memberFQName = mutableSetFQName + [memberName]
        guard symbols.lookupAll(fqName: memberFQName).first(where: { symbolID in
            symbols.externalLinkName(for: symbolID) == "kk_mutable_set_remove"
        }) == nil else {
            return
        }
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
            flags: [.synthetic, .operatorFunction]
        )
        symbols.setParentSymbol(mutableSetInterfaceSymbol, for: memberSymbol)
        symbols.setExternalLinkName("kk_mutable_set_remove", for: memberSymbol)
        symbols.setFunctionSignature(
            FunctionSignature(
                receiverType: receiverType,
                parameterTypes: [typeParamType],
                returnType: types.unitType,
                typeParameterSymbols: [typeParamSymbol],
                classTypeParameterCount: 1
            ),
            for: memberSymbol
        )
    }

    private func registerMutableSetMinusAssignCollectionMember(
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner,
        mutableSetFQName: [InternedString],
        mutableSetInterfaceSymbol: SymbolID,
        collectionInterfaceSymbol: SymbolID,
        typeParamSymbol: SymbolID,
        typeParamType: TypeID
    ) {
        let memberName = interner.intern("minusAssign")
        let memberFQName = mutableSetFQName + [memberName]
        guard symbols.lookupAll(fqName: memberFQName).first(where: { symbolID in
            symbols.externalLinkName(for: symbolID) == "kk_mutable_set_removeAll"
        }) == nil else {
            return
        }
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
            flags: [.synthetic, .operatorFunction]
        )
        symbols.setParentSymbol(mutableSetInterfaceSymbol, for: memberSymbol)
        symbols.setExternalLinkName("kk_mutable_set_removeAll", for: memberSymbol)
        symbols.setFunctionSignature(
            FunctionSignature(
                receiverType: receiverType,
                parameterTypes: [collectionType],
                returnType: types.unitType,
                typeParameterSymbols: [typeParamSymbol],
                classTypeParameterCount: 1
            ),
            for: memberSymbol
        )
    }

    private func registerMutableSetRetainAllMember(
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner,
        mutableSetFQName: [InternedString],
        mutableSetInterfaceSymbol: SymbolID,
        collectionInterfaceSymbol: SymbolID,
        typeParamSymbol: SymbolID,
        typeParamType: TypeID
    ) {
        let memberName = interner.intern("retainAll")
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
        symbols.setExternalLinkName("kk_mutable_set_retainAll", for: memberSymbol)
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
}
