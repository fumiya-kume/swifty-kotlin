extension DataFlowSemaPhase {
    func registerSyntheticURLStubs(
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
        let urlSymbol = ensureClassSymbol(
            named: "URL",
            in: javaNetPkg,
            symbols: symbols,
            interner: interner
        )
        let uriSymbol = ensureClassSymbol(
            named: "URI",
            in: javaNetPkg,
            symbols: symbols,
            interner: interner
        )
        if let javaNetPkgSymbol {
            symbols.setParentSymbol(javaNetPkgSymbol, for: urlSymbol)
        }

        let urlType = types.make(.classType(ClassType(
            classSymbol: urlSymbol, args: [], nullability: .nonNull
        )))
        let uriType = types.make(.classType(ClassType(
            classSymbol: uriSymbol, args: [], nullability: .nonNull
        )))
        let boolType = types.make(.primitive(.boolean, .nonNull))
        let nullableStringType = types.makeNullable(types.stringType)
        let nullableAnyType = types.makeNullable(types.anyType)
        symbols.setPropertyType(urlType, for: urlSymbol)

        registerURLConstructor(
            ownerSymbol: urlSymbol,
            ownerType: urlType,
            parameters: [("spec", types.stringType)],
            externalLinkName: "kk_url_new",
            symbols: symbols,
            interner: interner
        )
        registerURLConstructor(
            ownerSymbol: urlSymbol,
            ownerType: urlType,
            parameters: [("base", urlType), ("relative", types.stringType)],
            externalLinkName: "kk_url_new_relative",
            symbols: symbols,
            interner: interner
        )

        for (name, link, type) in [
            ("protocol", "kk_url_protocol", types.stringType),
            ("host", "kk_url_host", types.stringType),
            ("port", "kk_url_port", types.intType),
            ("path", "kk_url_path", types.stringType),
            ("query", "kk_url_query", nullableStringType),
            ("fragment", "kk_url_fragment", nullableStringType),
        ] as [(String, String, TypeID)] {
            registerURLMemberProperty(
                named: name,
                externalLinkName: link,
                ownerSymbol: urlSymbol,
                returnType: type,
                symbols: symbols,
                interner: interner
            )
        }

        registerURLMemberFunction(
            named: "toURI",
            externalLinkName: "kk_url_toURI",
            ownerSymbol: urlSymbol,
            ownerType: urlType,
            parameters: [],
            returnType: uriType,
            symbols: symbols,
            interner: interner
        )
        registerURLMemberFunction(
            named: "toExternalForm",
            externalLinkName: "kk_url_toExternalForm",
            ownerSymbol: urlSymbol,
            ownerType: urlType,
            parameters: [],
            returnType: types.stringType,
            symbols: symbols,
            interner: interner
        )
        registerURLMemberFunction(
            named: "sameFile",
            externalLinkName: "kk_url_sameFile",
            ownerSymbol: urlSymbol,
            ownerType: urlType,
            parameters: [("other", urlType)],
            returnType: boolType,
            symbols: symbols,
            interner: interner
        )
        registerURLMemberFunction(
            named: "equals",
            externalLinkName: "kk_url_equals",
            ownerSymbol: urlSymbol,
            ownerType: urlType,
            parameters: [("other", nullableAnyType)],
            returnType: boolType,
            symbols: symbols,
            interner: interner
        )
        registerURLMemberFunction(
            named: "hashCode",
            externalLinkName: "kk_url_hashCode",
            ownerSymbol: urlSymbol,
            ownerType: urlType,
            parameters: [],
            returnType: types.intType,
            symbols: symbols,
            interner: interner
        )
    }

    private func registerURLConstructor(
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
        let alreadyRegistered = symbols.lookupAll(fqName: ctorFQName).contains { symbol in
            guard let signature = symbols.functionSignature(for: symbol) else { return false }
            return signature.parameterTypes == parameters.map(\.type)
        }
        guard !alreadyRegistered else { return }
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

    private func registerURLMemberProperty(
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

    private func registerURLMemberFunction(
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
        let existing = symbols.lookupAll(fqName: functionFQName).contains { symbol in
            guard let signature = symbols.functionSignature(for: symbol) else { return false }
            return signature.receiverType == ownerType
                && signature.parameterTypes == parameters.map(\.type)
                && signature.returnType == returnType
        }
        guard !existing else { return }
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
                valueParameterSymbols: valueParameterSymbols,
                valueParameterHasDefaultValues: Array(repeating: false, count: valueParameterSymbols.count),
                valueParameterIsVararg: Array(repeating: false, count: valueParameterSymbols.count)
            ),
            for: functionSymbol
        )
    }
}
