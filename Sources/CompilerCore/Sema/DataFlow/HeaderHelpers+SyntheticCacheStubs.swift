extension DataFlowSemaPhase {
    func registerSyntheticCacheStubs(
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner
    ) {
        let kotlinPkg = ensurePackage(path: ["kotlin"], symbols: symbols, interner: interner)
        let cacheSymbol = ensureClassSymbol(named: "Cache", in: kotlinPkg, symbols: symbols, interner: interner)
        if let pkg = symbols.lookup(fqName: kotlinPkg) { symbols.setParentSymbol(pkg, for: cacheSymbol) }
        let cacheType = types.make(.classType(ClassType(classSymbol: cacheSymbol, args: [], nullability: .nonNull)))
        symbols.setPropertyType(cacheType, for: cacheSymbol)

        let initName = interner.intern("<init>")
        let ctorFq = [interner.intern("kotlin"), interner.intern("Cache"), initName]
        let ctor = symbols.define(kind: .constructor, name: initName, fqName: ctorFq, declSite: nil, visibility: .public, flags: [.synthetic])
        symbols.setParentSymbol(cacheSymbol, for: ctor)
        symbols.setExternalLinkName("kk_cache_new", for: ctor)
        symbols.setFunctionSignature(FunctionSignature(parameterTypes: [types.intType], returnType: cacheType, valueParameterSymbols: [], valueParameterHasDefaultValues: [], valueParameterIsVararg: []), for: ctor)

        for (name, params, ret, link) in [
            ("put", [types.intType, types.intType], types.unitType, "kk_cache_put"),
            ("get", [types.intType], types.makeNullable(types.intType), "kk_cache_get"),
            ("size", [], types.intType, "kk_cache_size"),
        ] as [(String, [TypeID], TypeID, String)] {
            let fn = interner.intern(name)
            let fq = [interner.intern("kotlin"), interner.intern("Cache"), fn]
            let sym = symbols.define(kind: .function, name: fn, fqName: fq, declSite: nil, visibility: .public, flags: [.synthetic])
            symbols.setParentSymbol(cacheSymbol, for: sym)
            symbols.setExternalLinkName(link, for: sym)
            symbols.setFunctionSignature(FunctionSignature(receiverType: cacheType, parameterTypes: params, returnType: ret, valueParameterSymbols: [], valueParameterHasDefaultValues: [], valueParameterIsVararg: []), for: sym)
        }
    }
}
