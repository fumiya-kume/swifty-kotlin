import Foundation

/// Synthetic Kotlin/JS collections `JsReadonlySet<E>.toSet()` conversion surface.
extension DataFlowSemaPhase {
    func registerSyntheticJsCollectionsReadonlySetToSetStubs(
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner
    ) {
        let pkg = ensurePackage(
            path: ["kotlin", "js", "collections"],
            symbols: symbols,
            interner: interner
        )
        let collectionsPkg = ensurePackage(
            path: ["kotlin", "collections"],
            symbols: symbols,
            interner: interner
        )
        let readonlySet = ensureJsReadonlySetCollectionsType(
            packageFQName: pkg,
            symbols: symbols,
            types: types,
            interner: interner
        )
        guard let setSymbol = symbols.lookup(fqName: collectionsPkg + [interner.intern("Set")]) else {
            return
        }

        let typeParamType = types.make(.typeParam(TypeParamType(
            symbol: readonlySet.typeParameterSymbol,
            nullability: .nonNull
        )))
        let receiverType = types.make(.classType(ClassType(
            classSymbol: readonlySet.symbol,
            args: [.out(typeParamType)],
            nullability: .nonNull
        )))
        let returnType = types.make(.classType(ClassType(
            classSymbol: setSymbol,
            args: [.out(typeParamType)],
            nullability: .nonNull
        )))

        registerJsReadonlySetToSetMember(
            ownerSymbol: readonlySet.symbol,
            ownerType: receiverType,
            returnType: returnType,
            typeParamSymbol: readonlySet.typeParameterSymbol,
            symbols: symbols,
            interner: interner
        )
    }

    private func registerJsReadonlySetToSetMember(
        ownerSymbol: SymbolID,
        ownerType: TypeID,
        returnType: TypeID,
        typeParamSymbol: SymbolID,
        symbols: SymbolTable,
        interner: StringInterner
    ) {
        guard let ownerInfo = symbols.symbol(ownerSymbol) else {
            return
        }
        let functionName = interner.intern("toSet")
        let functionFQName = ownerInfo.fqName + [functionName]
        let externalLinkName = "kk_js_set_toSet"

        if let existing = symbols.lookupAll(fqName: functionFQName).first(where: { symbol in
            guard let signature = symbols.functionSignature(for: symbol) else {
                return false
            }
            return signature.receiverType == ownerType
                && signature.parameterTypes.isEmpty
                && signature.returnType == returnType
                && signature.typeParameterSymbols == [typeParamSymbol]
                && signature.classTypeParameterCount == 1
        }) {
            symbols.setExternalLinkName(externalLinkName, for: existing)
            appendJsCollectionsSetAnnotation(to: existing, symbols: symbols)
            return
        }

        let functionSymbol = symbols.define(
            kind: .function,
            name: functionName,
            fqName: functionFQName,
            declSite: nil,
            visibility: .public,
            flags: [.synthetic]
        )
        symbols.setParentSymbol(ownerSymbol, for: functionSymbol)
        symbols.setExternalLinkName(externalLinkName, for: functionSymbol)
        appendJsCollectionsSetAnnotation(to: functionSymbol, symbols: symbols)
        symbols.setFunctionSignature(
            FunctionSignature(
                receiverType: ownerType,
                parameterTypes: [],
                returnType: returnType,
                typeParameterSymbols: [typeParamSymbol],
                classTypeParameterCount: 1
            ),
            for: functionSymbol
        )
    }

}
