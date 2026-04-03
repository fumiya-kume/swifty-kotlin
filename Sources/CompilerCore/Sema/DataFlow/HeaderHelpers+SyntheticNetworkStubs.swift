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
        let javaNetHttpPkgSymbol = symbols.lookup(fqName: javaNetHttpPkg)

        let httpClientSymbol = ensureClassSymbol(named: "HttpClient", in: javaNetHttpPkg, symbols: symbols, interner: interner)
        let httpRequestSymbol = ensureClassSymbol(named: "HttpRequest", in: javaNetHttpPkg, symbols: symbols, interner: interner)
        let httpResponseSymbol = ensureClassSymbol(named: "HttpResponse", in: javaNetHttpPkg, symbols: symbols, interner: interner)
        let httpHeadersSymbol = ensureClassSymbol(named: "HttpHeaders", in: javaNetHttpPkg, symbols: symbols, interner: interner)

        for symbol in [httpClientSymbol, httpRequestSymbol, httpResponseSymbol, httpHeadersSymbol] {
            if let javaNetHttpPkgSymbol {
                symbols.setParentSymbol(javaNetHttpPkgSymbol, for: symbol)
            }
        }

        let httpRequestBuilderSymbol = ensureNestedClassSymbol(named: "Builder", ownerSymbol: httpRequestSymbol, symbols: symbols, interner: interner)
        let httpRequestBodyPublisherSymbol = ensureNestedClassSymbol(named: "BodyPublisher", ownerSymbol: httpRequestSymbol, symbols: symbols, interner: interner)
        let httpResponseBodyHandlerSymbol = ensureNestedClassSymbol(named: "BodyHandler", ownerSymbol: httpResponseSymbol, symbols: symbols, interner: interner)
        let httpRequestBodyPublishersSymbol = ensureNestedObjectSymbol(named: "BodyPublishers", ownerSymbol: httpRequestSymbol, symbols: symbols, interner: interner)
        let httpResponseBodyHandlersSymbol = ensureNestedObjectSymbol(named: "BodyHandlers", ownerSymbol: httpResponseSymbol, symbols: symbols, interner: interner)

        let httpClientType = nominalType(httpClientSymbol, types: types)
        let httpRequestType = nominalType(httpRequestSymbol, types: types)
        let httpResponseType = nominalType(httpResponseSymbol, types: types)
        let httpHeadersType = nominalType(httpHeadersSymbol, types: types)
        let httpRequestBuilderType = nominalType(httpRequestBuilderSymbol, types: types)
        let httpRequestBodyPublisherType = nominalType(httpRequestBodyPublisherSymbol, types: types)
        let httpResponseBodyHandlerType = nominalType(httpResponseBodyHandlerSymbol, types: types)
        let httpRequestBodyPublishersType = nominalType(httpRequestBodyPublishersSymbol, types: types)
        let httpResponseBodyHandlersType = nominalType(httpResponseBodyHandlersSymbol, types: types)

        for (symbol, type) in [
            (httpClientSymbol, httpClientType),
            (httpRequestSymbol, httpRequestType),
            (httpResponseSymbol, httpResponseType),
            (httpHeadersSymbol, httpHeadersType),
            (httpRequestBuilderSymbol, httpRequestBuilderType),
            (httpRequestBodyPublisherSymbol, httpRequestBodyPublisherType),
            (httpResponseBodyHandlerSymbol, httpResponseBodyHandlerType),
            (httpRequestBodyPublishersSymbol, httpRequestBodyPublishersType),
            (httpResponseBodyHandlersSymbol, httpResponseBodyHandlersType),
        ] {
            symbols.setPropertyType(type, for: symbol)
        }

        let uriSymbol = symbols.lookup(fqName: [interner.intern("java"), interner.intern("net"), interner.intern("URI")])
        let uriType = uriSymbol.map { nominalType($0, types: types) } ?? types.anyType

        let listSymbol = symbols.lookup(fqName: [interner.intern("kotlin"), interner.intern("collections"), interner.intern("List")])
        let mapSymbol = symbols.lookup(fqName: [interner.intern("kotlin"), interner.intern("collections"), interner.intern("Map")])
        let listOfStringType: TypeID = if let listSymbol {
            types.make(.classType(ClassType(classSymbol: listSymbol, args: [.out(types.stringType)], nullability: .nonNull)))
        } else {
            types.anyType
        }
        let mapOfStringToListType: TypeID = if let mapSymbol {
            types.make(.classType(ClassType(classSymbol: mapSymbol, args: [.out(types.stringType), .out(listOfStringType)], nullability: .nonNull)))
        } else {
            types.anyType
        }
        let nullableStringType = types.makeNullable(types.stringType)

        registerStaticMethod(
            named: "newHttpClient",
            externalLinkName: "kk_http_client_newHttpClient",
            ownerSymbol: httpClientSymbol,
            parameters: [],
            returnType: httpClientType,
            symbols: symbols,
            interner: interner
        )

        registerMemberMethod(
            named: "send",
            externalLinkName: "kk_http_client_send",
            ownerSymbol: httpClientSymbol,
            ownerType: httpClientType,
            parameters: [("request", httpRequestType), ("bodyHandler", httpResponseBodyHandlerType)],
            returnType: httpResponseType,
            canThrow: true,
            symbols: symbols,
            interner: interner
        )

        registerStaticMethod(
            named: "newBuilder",
            externalLinkName: "kk_http_request_newBuilder",
            ownerSymbol: httpRequestSymbol,
            parameters: [],
            returnType: httpRequestBuilderType,
            symbols: symbols,
            interner: interner
        )

        registerStaticMethod(
            named: "newBuilder",
            externalLinkName: "kk_http_request_newBuilder_uri",
            ownerSymbol: httpRequestSymbol,
            parameters: [("uri", uriType)],
            returnType: httpRequestBuilderType,
            symbols: symbols,
            interner: interner
        )

        registerMemberMethod(
            named: "uri",
            externalLinkName: "kk_http_request_builder_uri",
            ownerSymbol: httpRequestBuilderSymbol,
            ownerType: httpRequestBuilderType,
            parameters: [("uri", uriType)],
            returnType: httpRequestBuilderType,
            symbols: symbols,
            interner: interner
        )

        registerMemberMethod(
            named: "header",
            externalLinkName: "kk_http_request_builder_header",
            ownerSymbol: httpRequestBuilderSymbol,
            ownerType: httpRequestBuilderType,
            parameters: [("name", types.stringType), ("value", types.stringType)],
            returnType: httpRequestBuilderType,
            symbols: symbols,
            interner: interner
        )

        registerMemberMethod(
            named: "GET",
            externalLinkName: "kk_http_request_builder_GET",
            ownerSymbol: httpRequestBuilderSymbol,
            ownerType: httpRequestBuilderType,
            parameters: [],
            returnType: httpRequestBuilderType,
            symbols: symbols,
            interner: interner
        )

        registerMemberMethod(
            named: "POST",
            externalLinkName: "kk_http_request_builder_POST",
            ownerSymbol: httpRequestBuilderSymbol,
            ownerType: httpRequestBuilderType,
            parameters: [("publisher", httpRequestBodyPublisherType)],
            returnType: httpRequestBuilderType,
            symbols: symbols,
            interner: interner
        )

        registerMemberMethod(
            named: "build",
            externalLinkName: "kk_http_request_builder_build",
            ownerSymbol: httpRequestBuilderSymbol,
            ownerType: httpRequestBuilderType,
            parameters: [],
            returnType: httpRequestType,
            canThrow: true,
            symbols: symbols,
            interner: interner
        )

        registerObjectMethod(
            named: "noBody",
            externalLinkName: "kk_http_body_publishers_noBody",
            ownerSymbol: httpRequestBodyPublishersSymbol,
            ownerType: httpRequestBodyPublishersType,
            parameters: [],
            returnType: httpRequestBodyPublisherType,
            symbols: symbols,
            interner: interner
        )

        registerObjectMethod(
            named: "ofString",
            externalLinkName: "kk_http_body_publishers_ofString",
            ownerSymbol: httpRequestBodyPublishersSymbol,
            ownerType: httpRequestBodyPublishersType,
            parameters: [("body", types.stringType)],
            returnType: httpRequestBodyPublisherType,
            symbols: symbols,
            interner: interner
        )

        registerObjectMethod(
            named: "ofString",
            externalLinkName: "kk_http_body_handlers_ofString",
            ownerSymbol: httpResponseBodyHandlersSymbol,
            ownerType: httpResponseBodyHandlersType,
            parameters: [],
            returnType: httpResponseBodyHandlerType,
            symbols: symbols,
            interner: interner
        )

        registerMemberMethod(
            named: "statusCode",
            externalLinkName: "kk_http_response_statusCode",
            ownerSymbol: httpResponseSymbol,
            ownerType: httpResponseType,
            parameters: [],
            returnType: types.intType,
            symbols: symbols,
            interner: interner
        )

        registerMemberMethod(
            named: "body",
            externalLinkName: "kk_http_response_body",
            ownerSymbol: httpResponseSymbol,
            ownerType: httpResponseType,
            parameters: [],
            returnType: types.stringType,
            symbols: symbols,
            interner: interner
        )

        registerMemberMethod(
            named: "headers",
            externalLinkName: "kk_http_response_headers",
            ownerSymbol: httpResponseSymbol,
            ownerType: httpResponseType,
            parameters: [],
            returnType: httpHeadersType,
            symbols: symbols,
            interner: interner
        )

        registerMemberMethod(
            named: "map",
            externalLinkName: "kk_http_headers_map",
            ownerSymbol: httpHeadersSymbol,
            ownerType: httpHeadersType,
            parameters: [],
            returnType: mapOfStringToListType,
            symbols: symbols,
            interner: interner
        )

        registerMemberMethod(
            named: "firstValue",
            externalLinkName: "kk_http_headers_firstValue",
            ownerSymbol: httpHeadersSymbol,
            ownerType: httpHeadersType,
            parameters: [("name", types.stringType)],
            returnType: nullableStringType,
            symbols: symbols,
            interner: interner
        )
    }

    private func nominalType(_ symbol: SymbolID, types: TypeSystem) -> TypeID {
        types.make(.classType(ClassType(classSymbol: symbol, args: [], nullability: .nonNull)))
    }

    private func ensureNestedClassSymbol(
        named name: String,
        ownerSymbol: SymbolID,
        symbols: SymbolTable,
        interner: StringInterner
    ) -> SymbolID {
        guard let ownerInfo = symbols.symbol(ownerSymbol) else { return .invalid }
        let nestedName = interner.intern(name)
        let nestedFQName = ownerInfo.fqName + [nestedName]
        if let existing = symbols.lookup(fqName: nestedFQName) {
            return existing
        }
        let nestedSymbol = symbols.define(
            kind: .class,
            name: nestedName,
            fqName: nestedFQName,
            declSite: nil,
            visibility: .public,
            flags: [.synthetic, .static]
        )
        symbols.setParentSymbol(ownerSymbol, for: nestedSymbol)
        return nestedSymbol
    }

    private func ensureNestedObjectSymbol(
        named name: String,
        ownerSymbol: SymbolID,
        symbols: SymbolTable,
        interner: StringInterner
    ) -> SymbolID {
        guard let ownerInfo = symbols.symbol(ownerSymbol) else { return .invalid }
        let nestedName = interner.intern(name)
        let nestedFQName = ownerInfo.fqName + [nestedName]
        if let existing = symbols.lookup(fqName: nestedFQName) {
            return existing
        }
        let nestedSymbol = symbols.define(
            kind: .object,
            name: nestedName,
            fqName: nestedFQName,
            declSite: nil,
            visibility: .public,
            flags: [.synthetic, .static]
        )
        symbols.setParentSymbol(ownerSymbol, for: nestedSymbol)
        return nestedSymbol
    }

    private func registerStaticMethod(
        named name: String,
        externalLinkName: String,
        ownerSymbol: SymbolID,
        parameters: [(name: String, type: TypeID)],
        returnType: TypeID,
        canThrow: Bool = false,
        symbols: SymbolTable,
        interner: StringInterner
    ) {
        guard let ownerInfo = symbols.symbol(ownerSymbol) else { return }
        let functionName = interner.intern(name)
        let functionFQName = ownerInfo.fqName + [functionName]
        let existing = symbols.lookupAll(fqName: functionFQName).first(where: {
            guard let signature = symbols.functionSignature(for: $0) else { return false }
            return signature.receiverType == nil && signature.parameterTypes == parameters.map(\.type)
        })
        if existing != nil { return }

        var flags: SymbolFlags = [.synthetic, .static]
        if canThrow { flags.formUnion([.throwingFunction]) }
        let functionSymbol = symbols.define(kind: .function, name: functionName, fqName: functionFQName, declSite: nil, visibility: .public, flags: flags)
        symbols.setParentSymbol(ownerSymbol, for: functionSymbol)
        symbols.setExternalLinkName(externalLinkName, for: functionSymbol)
        let valueParameterSymbols = defineParameters(for: functionSymbol, baseFQName: functionFQName, parameters: parameters, symbols: symbols, interner: interner)
        symbols.setFunctionSignature(
            FunctionSignature(
                parameterTypes: parameters.map(\.type),
                returnType: returnType,
                valueParameterSymbols: valueParameterSymbols,
                valueParameterHasDefaultValues: Array(repeating: false, count: valueParameterSymbols.count),
                valueParameterIsVararg: Array(repeating: false, count: valueParameterSymbols.count)
            ),
            for: functionSymbol
        )
    }

    private func registerMemberMethod(
        named name: String,
        externalLinkName: String,
        ownerSymbol: SymbolID,
        ownerType: TypeID,
        parameters: [(name: String, type: TypeID)],
        returnType: TypeID,
        canThrow: Bool = false,
        symbols: SymbolTable,
        interner: StringInterner
    ) {
        guard let ownerInfo = symbols.symbol(ownerSymbol) else { return }
        let functionName = interner.intern(name)
        let functionFQName = ownerInfo.fqName + [functionName]
        let existing = symbols.lookupAll(fqName: functionFQName).first(where: {
            guard let signature = symbols.functionSignature(for: $0) else { return false }
            return signature.receiverType == ownerType && signature.parameterTypes == parameters.map(\.type)
        })
        if existing != nil { return }

        var flags: SymbolFlags = [.synthetic]
        if canThrow { flags.formUnion([.throwingFunction]) }
        let functionSymbol = symbols.define(kind: .function, name: functionName, fqName: functionFQName, declSite: nil, visibility: .public, flags: flags)
        symbols.setParentSymbol(ownerSymbol, for: functionSymbol)
        symbols.setExternalLinkName(externalLinkName, for: functionSymbol)
        let valueParameterSymbols = defineParameters(for: functionSymbol, baseFQName: functionFQName, parameters: parameters, symbols: symbols, interner: interner)
        symbols.setFunctionSignature(
            FunctionSignature(
                receiverType: ownerType,
                parameterTypes: parameters.map(\.type),
                returnType: returnType,
                valueParameterSymbols: valueParameterSymbols,
                valueParameterHasDefaultValues: Array(repeating: false, count: valueParameterSymbols.count),
                valueParameterIsVararg: Array(repeating: false, count: valueParameterSymbols.count)
            ),
            for: functionSymbol
        )
    }

    private func registerObjectMethod(
        named name: String,
        externalLinkName: String,
        ownerSymbol: SymbolID,
        ownerType: TypeID,
        parameters: [(name: String, type: TypeID)],
        returnType: TypeID,
        symbols: SymbolTable,
        interner: StringInterner
    ) {
        registerMemberMethod(
            named: name,
            externalLinkName: externalLinkName,
            ownerSymbol: ownerSymbol,
            ownerType: ownerType,
            parameters: parameters,
            returnType: returnType,
            symbols: symbols,
            interner: interner
        )
    }

    private func defineParameters(
        for functionSymbol: SymbolID,
        baseFQName: [InternedString],
        parameters: [(name: String, type: TypeID)],
        symbols: SymbolTable,
        interner: StringInterner
    ) -> [SymbolID] {
        parameters.map { parameter in
            let parameterName = interner.intern(parameter.name)
            let parameterSymbol = symbols.define(
                kind: .valueParameter,
                name: parameterName,
                fqName: baseFQName + [parameterName],
                declSite: nil,
                visibility: .private,
                flags: [.synthetic]
            )
            symbols.setParentSymbol(functionSymbol, for: parameterSymbol)
            return parameterSymbol
        }
    }
}
