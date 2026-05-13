extension DataFlowSemaPhase {
    func registerMutableCollectionSequenceAddAllMembers(
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner,
        mutableCollectionSymbol: SymbolID,
        mutableListSymbol: SymbolID,
        mutableSetSymbol: SymbolID,
        sequenceSymbol: SymbolID
    ) {
        registerMutableCollectionSequenceAddAllMember(
            symbols: symbols,
            types: types,
            interner: interner,
            ownerSymbol: mutableCollectionSymbol,
            externalLinkName: "kk_mutable_collection_addAll_sequence",
            flags: [.synthetic],
            sequenceSymbol: sequenceSymbol
        )
        registerMutableCollectionSequenceAddAllMember(
            symbols: symbols,
            types: types,
            interner: interner,
            ownerSymbol: mutableListSymbol,
            externalLinkName: "kk_mutable_list_addAll_sequence",
            flags: [.synthetic, .operatorFunction],
            sequenceSymbol: sequenceSymbol
        )
        registerMutableCollectionSequenceAddAllMember(
            symbols: symbols,
            types: types,
            interner: interner,
            ownerSymbol: mutableSetSymbol,
            externalLinkName: "kk_mutable_set_addAll_sequence",
            flags: [.synthetic],
            sequenceSymbol: sequenceSymbol
        )
    }

    private func registerMutableCollectionSequenceAddAllMember(
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner,
        ownerSymbol: SymbolID,
        externalLinkName: String,
        flags: SymbolFlags,
        sequenceSymbol: SymbolID
    ) {
        guard let ownerFQName = symbols.symbol(ownerSymbol)?.fqName,
              let typeParamSymbol = types.nominalTypeParameterSymbols(for: ownerSymbol).first
        else {
            return
        }

        let memberName = interner.intern("addAll")
        let memberFQName = ownerFQName + [memberName]
        let typeParamType = types.make(.typeParam(TypeParamType(
            symbol: typeParamSymbol,
            nullability: .nonNull
        )))
        let receiverType = types.make(.classType(ClassType(
            classSymbol: ownerSymbol,
            args: [.invariant(typeParamType)],
            nullability: .nonNull
        )))
        let sequenceType = types.make(.classType(ClassType(
            classSymbol: sequenceSymbol,
            args: [.out(typeParamType)],
            nullability: .nonNull
        )))

        guard symbols.lookupAll(fqName: memberFQName).first(where: { candidate in
            guard let signature = symbols.functionSignature(for: candidate) else { return false }
            return signature.parameterTypes == [sequenceType] &&
                signature.returnType == types.booleanType
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
                parameterTypes: [sequenceType],
                returnType: types.booleanType,
                typeParameterSymbols: [typeParamSymbol],
                classTypeParameterCount: 1
            ),
            for: memberSymbol
        )
    }
}
