extension DataFlowSemaPhase {
    func registerSyntheticNetworkStubs(
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner
    ) {
        let javaNetHttpPkg = ensurePackage(
            path: ["java", "net", "http"],
            symbols: symbols,
            interner: interner
        )
        let packageSymbol = symbols.lookup(fqName: javaNetHttpPkg)

        let clientSymbol = ensureClassSymbol(
            named: "HttpClient",
            in: javaNetHttpPkg,
            symbols: symbols,
            interner: interner
        )
        let responseSymbol = ensureClassSymbol(
            named: "HttpResponse",
            in: javaNetHttpPkg,
            symbols: symbols,
            interner: interner
        )
        if let packageSymbol {
            symbols.setParentSymbol(packageSymbol, for: clientSymbol)
            symbols.setParentSymbol(packageSymbol, for: responseSymbol)
        }

        let clientType = types.make(.classType(ClassType(
            classSymbol: clientSymbol,
            args: [],
            nullability: .nonNull
        )))
        let responseType = types.make(.classType(ClassType(
            classSymbol: responseSymbol,
            args: [],
            nullability: .nonNull
        )))
        let nullableStringType = types.makeNullable(types.stringType)

        symbols.setPropertyType(clientType, for: clientSymbol)
        symbols.setPropertyType(responseType, for: responseSymbol)

        registerNetworkConstructor(
            ownerSymbol: clientSymbol,
            ownerType: clientType,
            parameters: [],
            externalLinkName: "kk_http_client_new",
            symbols: symbols,
            interner: interner
        )

        registerNetworkMemberFunction(
            named: "setConnectTimeoutMillis",
            externalLinkName: "kk_http_client_setConnectTimeoutMillis",
            ownerSymbol: clientSymbol,
            ownerType: clientType,
            parameters: [("timeoutMillis", types.intType)],
            returnType: types.unitType,
            isSuspend: false,
            symbols: symbols,
            interner: interner
        )
        registerNetworkMemberFunction(
            named: "setReadTimeoutMillis",
            externalLinkName: "kk_http_client_setReadTimeoutMillis",
            ownerSymbol: clientSymbol,
            ownerType: clientType,
            parameters: [("timeoutMillis", types.intType)],
            returnType: types.unitType,
            isSuspend: false,
            symbols: symbols,
            interner: interner
        )
        registerNetworkMemberFunction(
            named: "setFollowRedirects",
            externalLinkName: "kk_http_client_setFollowRedirects",
            ownerSymbol: clientSymbol,
            ownerType: clientType,
            parameters: [("enabled", types.booleanType)],
            returnType: types.unitType,
            isSuspend: false,
            symbols: symbols,
            interner: interner
        )
        registerNetworkMemberFunction(
            named: "setDefaultHeader",
            externalLinkName: "kk_http_client_setDefaultHeader",
            ownerSymbol: clientSymbol,
            ownerType: clientType,
            parameters: [("name", types.stringType), ("value", types.stringType)],
            returnType: types.unitType,
            isSuspend: false,
            symbols: symbols,
            interner: interner
        )
        registerNetworkMemberFunction(
            named: "setBasicAuth",
            externalLinkName: "kk_http_client_setBasicAuth",
            ownerSymbol: clientSymbol,
            ownerType: clientType,
            parameters: [("username", types.stringType), ("password", types.stringType)],
            returnType: types.unitType,
            isSuspend: false,
            symbols: symbols,
            interner: interner
        )
        registerNetworkMemberFunction(
            named: "setBearerToken",
            externalLinkName: "kk_http_client_setBearerToken",
            ownerSymbol: clientSymbol,
            ownerType: clientType,
            parameters: [("token", types.stringType)],
            returnType: types.unitType,
            isSuspend: false,
            symbols: symbols,
            interner: interner
        )
        registerNetworkMemberFunction(
            named: "clearAuthentication",
            externalLinkName: "kk_http_client_clearAuthentication",
            ownerSymbol: clientSymbol,
            ownerType: clientType,
            parameters: [],
            returnType: types.unitType,
            isSuspend: false,
            symbols: symbols,
            interner: interner
        )
        registerNetworkMemberFunction(
            named: "get",
            externalLinkName: "kk_http_client_get",
            ownerSymbol: clientSymbol,
            ownerType: clientType,
            parameters: [("url", types.stringType)],
            returnType: responseType,
            isSuspend: false,
            symbols: symbols,
            interner: interner
        )
        registerNetworkMemberFunction(
            named: "post",
            externalLinkName: "kk_http_client_post",
            ownerSymbol: clientSymbol,
            ownerType: clientType,
            parameters: [("url", types.stringType), ("body", types.stringType)],
            returnType: responseType,
            isSuspend: false,
            symbols: symbols,
            interner: interner
        )
        registerNetworkMemberFunction(
            named: "getAsync",
            externalLinkName: "kk_http_client_get_async",
            ownerSymbol: clientSymbol,
            ownerType: clientType,
            parameters: [("url", types.stringType)],
            returnType: responseType,
            isSuspend: true,
            symbols: symbols,
            interner: interner
        )
        registerNetworkMemberFunction(
            named: "postAsync",
            externalLinkName: "kk_http_client_post_async",
            ownerSymbol: clientSymbol,
            ownerType: clientType,
            parameters: [("url", types.stringType), ("body", types.stringType)],
            returnType: responseType,
            isSuspend: true,
            symbols: symbols,
            interner: interner
        )

        for (name, link, type) in [
            ("statusCode", "kk_http_response_statusCode", types.intType),
            ("body", "kk_http_response_body", types.stringType),
            ("url", "kk_http_response_url", types.stringType),
            ("contentType", "kk_http_response_contentType", nullableStringType),
            ("errorMessage", "kk_http_response_errorMessage", nullableStringType),
            ("timedOut", "kk_http_response_timedOut", types.booleanType),
            ("isSuccessful", "kk_http_response_isSuccessful", types.booleanType),
        ] as [(String, String, TypeID)] {
            registerNetworkMemberProperty(
                named: name,
                externalLinkName: link,
                ownerSymbol: responseSymbol,
                returnType: type,
                symbols: symbols,
                interner: interner
            )
        }

        registerNetworkMemberFunction(
            named: "header",
            externalLinkName: "kk_http_response_header",
            ownerSymbol: responseSymbol,
            ownerType: responseType,
            parameters: [("name", types.stringType)],
            returnType: nullableStringType,
            isSuspend: false,
            symbols: symbols,
            interner: interner
        )
    }

    private func registerNetworkConstructor(
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

    private func registerNetworkMemberProperty(
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

    private func registerNetworkMemberFunction(
        named name: String,
        externalLinkName: String,
        ownerSymbol: SymbolID,
        ownerType: TypeID,
        parameters: [(name: String, type: TypeID)],
        returnType: TypeID,
        isSuspend: Bool,
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

        var valueParameterSymbols: [SymbolID] = []
        for parameter in parameters {
            let parameterName = interner.intern(parameter.name)
            let parameterSymbol = symbols.define(kind: .valueParameter, name: parameterName, fqName: functionFQName + [parameterName], declSite: nil, visibility: .private, flags: [.synthetic])
            symbols.setParentSymbol(functionSymbol, for: parameterSymbol)
            valueParameterSymbols.append(parameterSymbol)
        }

        symbols.setFunctionSignature(
            FunctionSignature(
                receiverType: ownerType,
                parameterTypes: parameters.map(\.type),
                returnType: returnType,
                isSuspend: isSuspend,
                valueParameterSymbols: valueParameterSymbols,
                valueParameterHasDefaultValues: Array(repeating: false, count: valueParameterSymbols.count),
                valueParameterIsVararg: Array(repeating: false, count: valueParameterSymbols.count)
            ),
            for: functionSymbol
        )
    }
}
