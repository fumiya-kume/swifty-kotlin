extension DataFlowSemaPhase {
    func registerSyntheticDateFormatStubs(
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner
    ) {
        let javaTextPkg = ensurePackage(path: ["java", "text"], symbols: symbols, interner: interner)
        let javaTextPkgSymbol = symbols.lookup(fqName: javaTextPkg)
        let dateFormatSymbol = ensureClassSymbol(named: "DateFormat", in: javaTextPkg, symbols: symbols, interner: interner)
        // NOTE: ensureClassSymbol/ensurePackage are idempotent, but the Locale symbol must already
        // exist in the symbol table (registered by registerSyntheticLocaleConstructorStubs).
        // The call order in HeaderHelpers.swift guarantees this; do not reorder those calls.
        _ = ensureClassSymbol(named: "Locale", in: ensurePackage(path: ["java", "util"], symbols: symbols, interner: interner), symbols: symbols, interner: interner)
        if let javaTextPkgSymbol { symbols.setParentSymbol(javaTextPkgSymbol, for: dateFormatSymbol) }
        let dateFormatType = types.make(.classType(ClassType(classSymbol: dateFormatSymbol, args: [], nullability: .nonNull)))
        symbols.setPropertyType(dateFormatType, for: dateFormatSymbol)

        // The second parameter (locale identifier) is passed as a String handle, not a Locale
        // object. The runtime function kk_dateformat_ofPattern calls dateFormatString(from:) which
        // expects a string pointer. Passing a Locale object handle here would cause a fatal error.
        registerDateFormatTopLevel(
            packageFQName: javaTextPkg,
            name: "ofPattern",
            parameterTypes: [types.stringType, types.stringType],
            returnType: dateFormatType,
            externalLinkName: "kk_dateformat_ofPattern",
            symbols: symbols,
            interner: interner
        )
        registerDateFormatTopLevel(
            packageFQName: javaTextPkg,
            name: "ofPattern",
            parameterTypes: [types.stringType, types.stringType, types.stringType],
            returnType: dateFormatType,
            externalLinkName: "kk_dateformat_ofPatternWithTimeZone",
            symbols: symbols,
            interner: interner
        )
        registerDateFormatTopLevel(
            packageFQName: javaTextPkg,
            name: "getDateInstance",
            parameterTypes: [types.stringType],
            returnType: dateFormatType,
            externalLinkName: "kk_dateformat_getDateInstance",
            symbols: symbols,
            interner: interner
        )
        registerDateFormatTopLevel(
            packageFQName: javaTextPkg,
            name: "getDateInstance",
            parameterTypes: [types.stringType, types.stringType],
            returnType: dateFormatType,
            externalLinkName: "kk_dateformat_getDateInstanceWithTimeZone",
            symbols: symbols,
            interner: interner
        )
        registerDateFormatTopLevel(
            packageFQName: javaTextPkg,
            name: "getTimeInstance",
            parameterTypes: [types.stringType],
            returnType: dateFormatType,
            externalLinkName: "kk_dateformat_getTimeInstance",
            symbols: symbols,
            interner: interner
        )
        registerDateFormatTopLevel(
            packageFQName: javaTextPkg,
            name: "getTimeInstance",
            parameterTypes: [types.stringType, types.stringType],
            returnType: dateFormatType,
            externalLinkName: "kk_dateformat_getTimeInstanceWithTimeZone",
            symbols: symbols,
            interner: interner
        )
        registerDateFormatTopLevel(
            packageFQName: javaTextPkg,
            name: "getDateTimeInstance",
            parameterTypes: [types.stringType],
            returnType: dateFormatType,
            externalLinkName: "kk_dateformat_getDateTimeInstance",
            symbols: symbols,
            interner: interner
        )
        registerDateFormatTopLevel(
            packageFQName: javaTextPkg,
            name: "getDateTimeInstance",
            parameterTypes: [types.stringType, types.stringType],
            returnType: dateFormatType,
            externalLinkName: "kk_dateformat_getDateTimeInstanceWithTimeZone",
            symbols: symbols,
            interner: interner
        )
        registerDateFormatMember(
            ownerSymbol: dateFormatSymbol,
            ownerType: dateFormatType,
            name: "format",
            parameterTypes: [types.longType],
            returnType: types.stringType,
            externalLinkName: "kk_dateformat_format",
            symbols: symbols,
            interner: interner
        )
    }

    private func registerDateFormatTopLevel(packageFQName: [InternedString], name: String, parameterTypes: [TypeID], returnType: TypeID, externalLinkName: String, symbols: SymbolTable, interner: StringInterner) {
        let functionName = interner.intern(name)
        let fqName = packageFQName + [functionName]
        guard symbols.lookupAll(fqName: fqName).first(where: { symbols.functionSignature(for: $0)?.parameterTypes == parameterTypes }) == nil else { return }
        let function = symbols.define(kind: .function, name: functionName, fqName: fqName, declSite: nil, visibility: .public, flags: [.synthetic])
        if let pkg = symbols.lookup(fqName: packageFQName) { symbols.setParentSymbol(pkg, for: function) }
        symbols.setExternalLinkName(externalLinkName, for: function)
        symbols.setFunctionSignature(FunctionSignature(parameterTypes: parameterTypes, returnType: returnType, valueParameterSymbols: [], valueParameterHasDefaultValues: [], valueParameterIsVararg: []), for: function)
    }

    private func registerDateFormatMember(ownerSymbol: SymbolID, ownerType: TypeID, name: String, parameterTypes: [TypeID], returnType: TypeID, externalLinkName: String, symbols: SymbolTable, interner: StringInterner) {
        guard let ownerInfo = symbols.symbol(ownerSymbol) else { return }
        let functionName = interner.intern(name)
        let fqName = ownerInfo.fqName + [functionName]
        guard symbols.lookupAll(fqName: fqName).first(where: { symbols.functionSignature(for: $0)?.parameterTypes == parameterTypes }) == nil else { return }
        let function = symbols.define(kind: .function, name: functionName, fqName: fqName, declSite: nil, visibility: .public, flags: [.synthetic])
        symbols.setParentSymbol(ownerSymbol, for: function)
        symbols.setExternalLinkName(externalLinkName, for: function)
        symbols.setFunctionSignature(FunctionSignature(receiverType: ownerType, parameterTypes: parameterTypes, returnType: returnType, valueParameterSymbols: [], valueParameterHasDefaultValues: [], valueParameterIsVararg: []), for: function)
    }
}
