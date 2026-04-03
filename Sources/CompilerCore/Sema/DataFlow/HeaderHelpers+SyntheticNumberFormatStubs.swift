extension DataFlowSemaPhase {
    func registerSyntheticNumberFormatStubs(
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner
    ) {
        let javaTextPkg = ensurePackage(path: ["java", "text"], symbols: symbols, interner: interner)
        let javaTextPkgSymbol = symbols.lookup(fqName: javaTextPkg)
        let javaUtilPkg = ensurePackage(path: ["java", "util"], symbols: symbols, interner: interner)

        let localeSymbol = ensureClassSymbol(named: "Locale", in: javaUtilPkg, symbols: symbols, interner: interner)
        let numberFormatSymbol = ensureClassSymbol(named: "NumberFormat", in: javaTextPkg, symbols: symbols, interner: interner)
        if let javaTextPkgSymbol {
            symbols.setParentSymbol(javaTextPkgSymbol, for: numberFormatSymbol)
        }
        let localeType = types.make(.classType(ClassType(classSymbol: localeSymbol, args: [], nullability: .nonNull)))
        let numberFormatType = types.make(.classType(ClassType(classSymbol: numberFormatSymbol, args: [], nullability: .nonNull)))
        symbols.setPropertyType(numberFormatType, for: numberFormatSymbol)

        registerNumberFormatTopLevel(
            packageFQName: javaTextPkg,
            name: "getIntegerInstance",
            parameterTypes: [localeType],
            returnType: numberFormatType,
            externalLinkName: "kk_numberformat_getIntegerInstance",
            symbols: symbols,
            interner: interner
        )
        registerNumberFormatTopLevel(
            packageFQName: javaTextPkg,
            name: "getNumberInstance",
            parameterTypes: [localeType],
            returnType: numberFormatType,
            externalLinkName: "kk_numberformat_getNumberInstance",
            symbols: symbols,
            interner: interner
        )
        registerNumberFormatTopLevel(
            packageFQName: javaTextPkg,
            name: "getCurrencyInstance",
            parameterTypes: [localeType],
            returnType: numberFormatType,
            externalLinkName: "kk_numberformat_getCurrencyInstance",
            symbols: symbols,
            interner: interner
        )
        registerNumberFormatTopLevel(
            packageFQName: javaTextPkg,
            name: "getPercentInstance",
            parameterTypes: [localeType],
            returnType: numberFormatType,
            externalLinkName: "kk_numberformat_getPercentInstance",
            symbols: symbols,
            interner: interner
        )

        registerNumberFormatMember(
            ownerSymbol: numberFormatSymbol,
            ownerType: numberFormatType,
            name: "format",
            parameterTypes: [types.intType],
            returnType: types.stringType,
            externalLinkName: "kk_numberformat_formatInt",
            symbols: symbols,
            interner: interner
        )
        registerNumberFormatMember(
            ownerSymbol: numberFormatSymbol,
            ownerType: numberFormatType,
            name: "format",
            parameterTypes: [types.longType],
            returnType: types.stringType,
            externalLinkName: "kk_numberformat_formatLong",
            symbols: symbols,
            interner: interner
        )
        registerNumberFormatMember(
            ownerSymbol: numberFormatSymbol,
            ownerType: numberFormatType,
            name: "format",
            parameterTypes: [types.floatType],
            returnType: types.stringType,
            externalLinkName: "kk_numberformat_formatFloat",
            symbols: symbols,
            interner: interner
        )
        registerNumberFormatMember(
            ownerSymbol: numberFormatSymbol,
            ownerType: numberFormatType,
            name: "format",
            parameterTypes: [types.doubleType],
            returnType: types.stringType,
            externalLinkName: "kk_numberformat_formatDouble",
            symbols: symbols,
            interner: interner
        )
    }

    private func registerNumberFormatTopLevel(
        packageFQName: [InternedString],
        name: String,
        parameterTypes: [TypeID],
        returnType: TypeID,
        externalLinkName: String,
        symbols: SymbolTable,
        interner: StringInterner
    ) {
        let functionName = interner.intern(name)
        let fqName = packageFQName + [functionName]
        if let existing = symbols.lookupAll(fqName: fqName).first(where: { symbolID in
            symbols.functionSignature(for: symbolID)?.parameterTypes == parameterTypes
        }) {
            symbols.setExternalLinkName(externalLinkName, for: existing)
            return
        }
        let function = symbols.define(kind: .function, name: functionName, fqName: fqName, declSite: nil, visibility: .public, flags: [.synthetic])
        if let pkg = symbols.lookup(fqName: packageFQName) {
            symbols.setParentSymbol(pkg, for: function)
        }
        symbols.setExternalLinkName(externalLinkName, for: function)
        symbols.setFunctionSignature(FunctionSignature(parameterTypes: parameterTypes, returnType: returnType, valueParameterSymbols: [], valueParameterHasDefaultValues: [], valueParameterIsVararg: []), for: function)
    }

    private func registerNumberFormatMember(
        ownerSymbol: SymbolID,
        ownerType: TypeID,
        name: String,
        parameterTypes: [TypeID],
        returnType: TypeID,
        externalLinkName: String,
        symbols: SymbolTable,
        interner: StringInterner
    ) {
        guard let ownerInfo = symbols.symbol(ownerSymbol) else { return }
        let functionName = interner.intern(name)
        let fqName = ownerInfo.fqName + [functionName]
        if let existing = symbols.lookupAll(fqName: fqName).first(where: { symbolID in
            guard let signature = symbols.functionSignature(for: symbolID) else { return false }
            return signature.receiverType == ownerType && signature.parameterTypes == parameterTypes
        }) {
            symbols.setExternalLinkName(externalLinkName, for: existing)
            return
        }
        let function = symbols.define(kind: .function, name: functionName, fqName: fqName, declSite: nil, visibility: .public, flags: [.synthetic])
        symbols.setParentSymbol(ownerSymbol, for: function)
        symbols.setExternalLinkName(externalLinkName, for: function)
        symbols.setFunctionSignature(FunctionSignature(receiverType: ownerType, parameterTypes: parameterTypes, returnType: returnType, valueParameterSymbols: [], valueParameterHasDefaultValues: [], valueParameterIsVararg: []), for: function)
    }
}
