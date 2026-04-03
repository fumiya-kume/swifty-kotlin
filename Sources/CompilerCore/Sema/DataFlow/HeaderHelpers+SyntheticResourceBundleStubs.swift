extension DataFlowSemaPhase {
    func registerSyntheticResourceBundleStubs(
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner
    ) {
        let javaUtilPkg = ensurePackage(path: ["java", "util"], symbols: symbols, interner: interner)
        let javaUtilPkgSymbol = symbols.lookup(fqName: javaUtilPkg)

        let localeSymbol = ensureClassSymbol(named: "Locale", in: javaUtilPkg, symbols: symbols, interner: interner)
        let bundleSymbol = ensureClassSymbol(named: "ResourceBundle", in: javaUtilPkg, symbols: symbols, interner: interner)
        if let javaUtilPkgSymbol {
            symbols.setParentSymbol(javaUtilPkgSymbol, for: localeSymbol)
            symbols.setParentSymbol(javaUtilPkgSymbol, for: bundleSymbol)
        }

        let localeType = types.make(.classType(ClassType(classSymbol: localeSymbol, args: [], nullability: .nonNull)))
        let bundleType = types.make(.classType(ClassType(classSymbol: bundleSymbol, args: [], nullability: .nonNull)))
        let listType: TypeID = if let listSymbol = symbols.lookup(fqName: [interner.intern("kotlin"), interner.intern("collections"), interner.intern("List")]) {
            types.make(.classType(ClassType(
                classSymbol: listSymbol,
                args: [.out(types.stringType)],
                nullability: .nonNull
            )))
        } else {
            types.anyType
        }
        symbols.setPropertyType(localeType, for: localeSymbol)
        symbols.setPropertyType(bundleType, for: bundleSymbol)

        registerRBConstructor(ownerSymbol: localeSymbol, ownerType: localeType, parameters: [("identifier", types.stringType)], externalLinkName: "kk_locale_new", symbols: symbols, interner: interner)
        registerRBTopLevelFunction(packageFQName: javaUtilPkg, name: "getBundle", parameterTypes: [types.stringType, localeType], returnType: bundleType, externalLinkName: "kk_resource_bundle_getBundle", symbols: symbols, interner: interner)
        registerRBMemberFunction(ownerSymbol: bundleSymbol, ownerType: bundleType, name: "getString", parameterTypes: [types.stringType], returnType: types.stringType, externalLinkName: "kk_resource_bundle_getString", symbols: symbols, interner: interner)
        registerRBMemberFunction(ownerSymbol: bundleSymbol, ownerType: bundleType, name: "getObject", parameterTypes: [types.stringType], returnType: types.anyType, externalLinkName: "kk_resource_bundle_getObject", symbols: symbols, interner: interner)
        registerRBMemberFunction(ownerSymbol: bundleSymbol, ownerType: bundleType, name: "getKeys", parameterTypes: [], returnType: listType, externalLinkName: "kk_resource_bundle_getKeys", symbols: symbols, interner: interner)
    }

    private func registerRBConstructor(ownerSymbol: SymbolID, ownerType: TypeID, parameters: [(String, TypeID)], externalLinkName: String, symbols: SymbolTable, interner: StringInterner) {
        guard let ownerInfo = symbols.symbol(ownerSymbol) else { return }
        let initName = interner.intern("<init>")
        let fqName = ownerInfo.fqName + [initName]
        guard symbols.lookupAll(fqName: fqName).isEmpty else { return }
        let ctor = symbols.define(kind: .constructor, name: initName, fqName: fqName, declSite: nil, visibility: .public, flags: [.synthetic])
        symbols.setParentSymbol(ownerSymbol, for: ctor)
        symbols.setExternalLinkName(externalLinkName, for: ctor)
        symbols.setFunctionSignature(FunctionSignature(parameterTypes: parameters.map(\.1), returnType: ownerType, valueParameterSymbols: [], valueParameterHasDefaultValues: [], valueParameterIsVararg: []), for: ctor)
    }

    private func registerRBTopLevelFunction(packageFQName: [InternedString], name: String, parameterTypes: [TypeID], returnType: TypeID, externalLinkName: String, symbols: SymbolTable, interner: StringInterner) {
        let functionName = interner.intern(name)
        let fqName = packageFQName + [functionName]
        guard symbols.lookupAll(fqName: fqName).isEmpty else { return }
        let function = symbols.define(kind: .function, name: functionName, fqName: fqName, declSite: nil, visibility: .public, flags: [.synthetic])
        if let pkg = symbols.lookup(fqName: packageFQName) { symbols.setParentSymbol(pkg, for: function) }
        symbols.setExternalLinkName(externalLinkName, for: function)
        symbols.setFunctionSignature(FunctionSignature(parameterTypes: parameterTypes, returnType: returnType, valueParameterSymbols: [], valueParameterHasDefaultValues: [], valueParameterIsVararg: []), for: function)
    }

    private func registerRBMemberFunction(ownerSymbol: SymbolID, ownerType: TypeID, name: String, parameterTypes: [TypeID], returnType: TypeID, externalLinkName: String, symbols: SymbolTable, interner: StringInterner) {
        guard let ownerInfo = symbols.symbol(ownerSymbol) else { return }
        let functionName = interner.intern(name)
        let fqName = ownerInfo.fqName + [functionName]
        guard symbols.lookupAll(fqName: fqName).isEmpty else { return }
        let function = symbols.define(kind: .function, name: functionName, fqName: fqName, declSite: nil, visibility: .public, flags: [.synthetic])
        symbols.setParentSymbol(ownerSymbol, for: function)
        symbols.setExternalLinkName(externalLinkName, for: function)
        symbols.setFunctionSignature(FunctionSignature(receiverType: ownerType, parameterTypes: parameterTypes, returnType: returnType, valueParameterSymbols: [], valueParameterHasDefaultValues: [], valueParameterIsVararg: []), for: function)
    }
}
