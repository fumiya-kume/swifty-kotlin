extension DataFlowSemaPhase {
    func registerSyntheticURIStubs(
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner
    ) {
        let javaNetPkg = ensurePackage(
            path: ["java", "net"],
            symbols: symbols,
            interner: interner
        )
        let javaNetPkgSymbol = symbols.lookup(fqName: javaNetPkg)
        let uriSymbol = ensureClassSymbol(
            named: "URI",
            in: javaNetPkg,
            symbols: symbols,
            interner: interner
        )
        if let javaNetPkgSymbol {
            symbols.setParentSymbol(javaNetPkgSymbol, for: uriSymbol)
        }

        let uriType = types.make(.classType(ClassType(
            classSymbol: uriSymbol, args: [], nullability: .nonNull
        )))
        let nullableStringType = types.makeNullable(types.stringType)
        symbols.setPropertyType(uriType, for: uriSymbol)

        registerURIConstructor(
            ownerSymbol: uriSymbol,
            ownerType: uriType,
            parameters: [("spec", types.stringType)],
            externalLinkName: "kk_uri_new",
            symbols: symbols,
            interner: interner
        )

        for (name, link, type) in [
            ("scheme", "kk_uri_scheme", nullableStringType),
            ("authority", "kk_uri_authority", nullableStringType),
            ("path", "kk_uri_path", types.stringType),
            ("query", "kk_uri_query", nullableStringType),
            ("fragment", "kk_uri_fragment", nullableStringType),
        ] as [(String, String, TypeID)] {
            registerURIMemberProperty(
                named: name,
                externalLinkName: link,
                ownerSymbol: uriSymbol,
                returnType: type,
                symbols: symbols,
                interner: interner
            )
        }

        registerURIMemberFunction(
            named: "toString",
            externalLinkName: "kk_uri_toString",
            ownerSymbol: uriSymbol,
            ownerType: uriType,
            parameters: [],
            returnType: types.stringType,
            symbols: symbols,
            interner: interner
        )
        registerURIMemberFunction(
            named: "normalize",
            externalLinkName: "kk_uri_normalize",
            ownerSymbol: uriSymbol,
            ownerType: uriType,
            parameters: [],
            returnType: uriType,
            symbols: symbols,
            interner: interner
        )
        registerURIMemberFunction(
            named: "resolve",
            externalLinkName: "kk_uri_resolve",
            ownerSymbol: uriSymbol,
            ownerType: uriType,
            parameters: [("other", types.stringType)],
            returnType: uriType,
            symbols: symbols,
            interner: interner
        )
        registerURIMemberFunction(
            named: "relativize",
            externalLinkName: "kk_uri_relativize",
            ownerSymbol: uriSymbol,
            ownerType: uriType,
            parameters: [("other", uriType)],
            returnType: uriType,
            symbols: symbols,
            interner: interner
        )
    }

    private func registerURIConstructor(
        ownerSymbol: SymbolID,
        ownerType: TypeID,
        parameters: [(name: String, type: TypeID)],
        externalLinkName: String,
        symbols: SymbolTable,
        interner: StringInterner
    ) {
        guard let ownerInfo = symbols.symbol(ownerSymbol) else { return }
        let initName = interner.intern("<init>")
        let ctorFQName = ownerInfo.fqName + [initName]
        guard symbols.lookupAll(fqName: ctorFQName).isEmpty else { return }
        let ctorSymbol = symbols.define(kind: .constructor, name: initName, fqName: ctorFQName, declSite: nil, visibility: .public, flags: [.synthetic])
        symbols.setParentSymbol(ownerSymbol, for: ctorSymbol)
        symbols.setExternalLinkName(externalLinkName, for: ctorSymbol)
        var valueParameterSymbols: [SymbolID] = []
        for parameter in parameters {
            let parameterName = interner.intern(parameter.name)
            let parameterSymbol = symbols.define(kind: .valueParameter, name: parameterName, fqName: ctorFQName + [parameterName], declSite: nil, visibility: .private, flags: [.synthetic])
            symbols.setParentSymbol(ctorSymbol, for: parameterSymbol)
            valueParameterSymbols.append(parameterSymbol)
        }
        symbols.setFunctionSignature(
            FunctionSignature(
                parameterTypes: parameters.map(\.type),
                returnType: ownerType,
                valueParameterSymbols: valueParameterSymbols,
                valueParameterHasDefaultValues: Array(repeating: false, count: valueParameterSymbols.count),
                valueParameterIsVararg: Array(repeating: false, count: valueParameterSymbols.count)
            ),
            for: ctorSymbol
        )
    }

    private func registerURIMemberProperty(
        named name: String,
        externalLinkName: String,
        ownerSymbol: SymbolID,
        returnType: TypeID,
        symbols: SymbolTable,
        interner: StringInterner
    ) {
        guard let ownerInfo = symbols.symbol(ownerSymbol) else { return }
        let propertyName = interner.intern(name)
        let propertyFQName = ownerInfo.fqName + [propertyName]
        guard symbols.lookupAll(fqName: propertyFQName).isEmpty else { return }
        let propertySymbol = symbols.define(kind: .property, name: propertyName, fqName: propertyFQName, declSite: nil, visibility: .public, flags: [.synthetic])
        symbols.setParentSymbol(ownerSymbol, for: propertySymbol)
        symbols.setExternalLinkName(externalLinkName, for: propertySymbol)
        symbols.setPropertyType(returnType, for: propertySymbol)
    }

    private func registerURIMemberFunction(
        named name: String,
        externalLinkName: String,
        ownerSymbol: SymbolID,
        ownerType: TypeID,
        parameters: [(name: String, type: TypeID)],
        returnType: TypeID,
        symbols: SymbolTable,
        interner: StringInterner
    ) {
        guard let ownerInfo = symbols.symbol(ownerSymbol) else { return }
        let functionName = interner.intern(name)
        let functionFQName = ownerInfo.fqName + [functionName]
        guard symbols.lookupAll(fqName: functionFQName).isEmpty else { return }
        let functionSymbol = symbols.define(kind: .function, name: functionName, fqName: functionFQName, declSite: nil, visibility: .public, flags: [.synthetic])
        symbols.setParentSymbol(ownerSymbol, for: functionSymbol)
        symbols.setExternalLinkName(externalLinkName, for: functionSymbol)
        symbols.setFunctionSignature(
            FunctionSignature(
                receiverType: ownerType,
                parameterTypes: parameters.map(\.type),
                returnType: returnType,
                valueParameterSymbols: [],
                valueParameterHasDefaultValues: [],
                valueParameterIsVararg: []
            ),
            for: functionSymbol
        )
    }
}
