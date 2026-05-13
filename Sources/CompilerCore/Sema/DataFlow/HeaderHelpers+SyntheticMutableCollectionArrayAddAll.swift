import Foundation

extension DataFlowSemaPhase {
    func registerMutableCollectionArrayAddAllMembers(
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner,
        kotlinCollectionsPkg: [InternedString]
    ) {
        let kotlinPkg: [InternedString] = [interner.intern("kotlin")]
        guard let arraySymbol = symbols.lookup(fqName: kotlinPkg + [interner.intern("Array")]) else {
            return
        }

        registerMutableCollectionArrayAddAllMember(
            ownerName: "MutableCollection",
            externalLinkName: "kk_mutable_collection_addAll",
            flags: [.synthetic],
            symbols: symbols,
            types: types,
            interner: interner,
            kotlinCollectionsPkg: kotlinCollectionsPkg,
            arraySymbol: arraySymbol
        )
        registerMutableCollectionArrayAddAllMember(
            ownerName: "MutableList",
            externalLinkName: "kk_mutable_list_addAll",
            flags: [.synthetic, .operatorFunction],
            symbols: symbols,
            types: types,
            interner: interner,
            kotlinCollectionsPkg: kotlinCollectionsPkg,
            arraySymbol: arraySymbol
        )
        registerMutableCollectionArrayAddAllMember(
            ownerName: "MutableSet",
            externalLinkName: "kk_mutable_set_addAll",
            flags: [.synthetic],
            symbols: symbols,
            types: types,
            interner: interner,
            kotlinCollectionsPkg: kotlinCollectionsPkg,
            arraySymbol: arraySymbol
        )
    }

    private func registerMutableCollectionArrayAddAllMember(
        ownerName: String,
        externalLinkName: String,
        flags: SymbolFlags,
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner,
        kotlinCollectionsPkg: [InternedString],
        arraySymbol: SymbolID
    ) {
        let ownerInternedName = interner.intern(ownerName)
        let ownerFQName = kotlinCollectionsPkg + [ownerInternedName]
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
        let arrayType = types.make(.classType(ClassType(
            classSymbol: arraySymbol,
            args: [.out(typeParamType)],
            nullability: .nonNull
        )))

        let memberName = interner.intern("addAll")
        let memberFQName = ownerFQName + [memberName]
        guard symbols.lookupAll(fqName: memberFQName).first(where: { symbolID in
            guard let signature = symbols.functionSignature(for: symbolID) else { return false }
            return signature.parameterTypes == [arrayType] && signature.returnType == types.booleanType
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
                parameterTypes: [arrayType],
                returnType: types.booleanType,
                typeParameterSymbols: [typeParamSymbol],
                classTypeParameterCount: 1
            ),
            for: memberSymbol
        )
    }
}
