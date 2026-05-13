extension DataFlowSemaPhase {
    func registerMutableCollectionIterableAddAllMembers(
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner,
        kotlinCollectionsPkg: [InternedString],
        iterableInterfaceSymbol: SymbolID
    ) {
        registerMutableCollectionIterableAddAllMember(
            ownerName: "MutableCollection",
            externalLinkName: "kk_mutable_collection_addAll_iterable",
            flags: [.synthetic],
            symbols: symbols,
            types: types,
            interner: interner,
            kotlinCollectionsPkg: kotlinCollectionsPkg,
            iterableInterfaceSymbol: iterableInterfaceSymbol
        )
        registerMutableCollectionIterableAddAllMember(
            ownerName: "MutableList",
            externalLinkName: "kk_mutable_list_addAll_iterable",
            flags: [.synthetic, .operatorFunction],
            symbols: symbols,
            types: types,
            interner: interner,
            kotlinCollectionsPkg: kotlinCollectionsPkg,
            iterableInterfaceSymbol: iterableInterfaceSymbol
        )
        registerMutableCollectionIterableAddAllMember(
            ownerName: "MutableSet",
            externalLinkName: "kk_mutable_set_addAll_iterable",
            flags: [.synthetic],
            symbols: symbols,
            types: types,
            interner: interner,
            kotlinCollectionsPkg: kotlinCollectionsPkg,
            iterableInterfaceSymbol: iterableInterfaceSymbol
        )
    }

    private func registerMutableCollectionIterableAddAllMember(
        ownerName: String,
        externalLinkName: String,
        flags: SymbolFlags,
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner,
        kotlinCollectionsPkg: [InternedString],
        iterableInterfaceSymbol: SymbolID
    ) {
        let ownerNameInterned = interner.intern(ownerName)
        let ownerFQName = kotlinCollectionsPkg + [ownerNameInterned]
        guard let ownerSymbol = symbols.lookup(fqName: ownerFQName),
              let typeParamSymbol = types.nominalTypeParameterSymbols(for: ownerSymbol).first
        else {
            return
        }

        let typeParamType = types.make(.typeParam(TypeParamType(
            symbol: typeParamSymbol,
            nullability: .nonNull
        )))
        let receiverType = types.make(.classType(ClassType(
            classSymbol: ownerSymbol,
            args: [.invariant(typeParamType)],
            nullability: .nonNull
        )))
        let iterableType = types.make(.classType(ClassType(
            classSymbol: iterableInterfaceSymbol,
            args: [.out(typeParamType)],
            nullability: .nonNull
        )))

        let memberName = interner.intern("addAll")
        let memberFQName = ownerFQName + [memberName]
        guard symbols.lookupAll(fqName: memberFQName).first(where: { symbolID in
            guard let signature = symbols.functionSignature(for: symbolID) else { return false }
            return signature.parameterTypes == [iterableType] && signature.returnType == types.booleanType
        }) == nil else {
            return
        }

        let memberSymbol = symbols.define(
            kind: .function,
            name: memberName,
            fqName: memberFQName,
            declSite: nil,
            visibility: .public,
            flags: flags
        )
        symbols.setParentSymbol(ownerSymbol, for: memberSymbol)
        symbols.setExternalLinkName(externalLinkName, for: memberSymbol)
        symbols.setFunctionSignature(
            FunctionSignature(
                receiverType: receiverType,
                parameterTypes: [iterableType],
                returnType: types.booleanType,
                typeParameterSymbols: [typeParamSymbol],
                classTypeParameterCount: 1
            ),
            for: memberSymbol
        )
    }
}
