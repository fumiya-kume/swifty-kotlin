extension DataFlowSemaPhase {
    func registerSyntheticLocaleConstructorStubs(
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner
    ) {
        let javaUtilPkg = ensurePackage(path: ["java", "util"], symbols: symbols, interner: interner)
        let javaUtilPkgSymbol = symbols.lookup(fqName: javaUtilPkg)
        let localeSymbol = ensureClassSymbol(named: "Locale", in: javaUtilPkg, symbols: symbols, interner: interner)
        if let javaUtilPkgSymbol { symbols.setParentSymbol(javaUtilPkgSymbol, for: localeSymbol) }
        let localeType = types.make(.classType(ClassType(classSymbol: localeSymbol, args: [], nullability: .nonNull)))
        symbols.setPropertyType(localeType, for: localeSymbol)

        guard let ownerInfo = symbols.symbol(localeSymbol) else { return }
        let initName = interner.intern("<init>")
        let fqName = ownerInfo.fqName + [initName]
        guard symbols.lookupAll(fqName: fqName).isEmpty else { return }
        let ctor = symbols.define(kind: .constructor, name: initName, fqName: fqName, declSite: nil, visibility: .public, flags: [.synthetic])
        symbols.setParentSymbol(localeSymbol, for: ctor)
        symbols.setExternalLinkName("kk_locale_new", for: ctor)
        symbols.setFunctionSignature(FunctionSignature(parameterTypes: [types.stringType], returnType: localeType, valueParameterSymbols: [], valueParameterHasDefaultValues: [], valueParameterIsVararg: []), for: ctor)
    }
}
