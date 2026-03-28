extension DataFlowSemaPhase {
    func registerSyntheticSecurityStubs(
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner
    ) {
        let securityPkg = ensurePackage(path: ["java", "security"], symbols: symbols, interner: interner)
        let securityPkgSymbol = symbols.lookup(fqName: securityPkg)
        let digestSymbol = ensureClassSymbol(named: "MessageDigest", in: securityPkg, symbols: symbols, interner: interner)
        if let securityPkgSymbol { symbols.setParentSymbol(securityPkgSymbol, for: digestSymbol) }
        let digestType = types.make(.classType(ClassType(classSymbol: digestSymbol, args: [], nullability: .nonNull)))
        let byteArrayType: TypeID = if let listSymbol = symbols.lookup(fqName: [interner.intern("kotlin"), interner.intern("collections"), interner.intern("List")]) {
            types.make(.classType(ClassType(classSymbol: listSymbol, args: [.out(types.intType)], nullability: .nonNull)))
        } else { types.anyType }
        symbols.setPropertyType(digestType, for: digestSymbol)

        registerDigestTopLevel(packageFQName: securityPkg, name: "getInstance", parameterTypes: [types.stringType], returnType: digestType, externalLinkName: "kk_message_digest_getInstance", symbols: symbols, interner: interner)
        registerDigestMember(ownerSymbol: digestSymbol, ownerType: digestType, name: "digest", parameterTypes: [byteArrayType], returnType: byteArrayType, externalLinkName: "kk_message_digest_digest", symbols: symbols, interner: interner)
    }

    private func registerDigestTopLevel(packageFQName: [InternedString], name: String, parameterTypes: [TypeID], returnType: TypeID, externalLinkName: String, symbols: SymbolTable, interner: StringInterner) {
        let fn = interner.intern(name)
        let fq = packageFQName + [fn]
        guard symbols.lookupAll(fqName: fq).isEmpty else { return }
        let sym = symbols.define(kind: .function, name: fn, fqName: fq, declSite: nil, visibility: .public, flags: [.synthetic])
        if let pkg = symbols.lookup(fqName: packageFQName) { symbols.setParentSymbol(pkg, for: sym) }
        symbols.setExternalLinkName(externalLinkName, for: sym)
        symbols.setFunctionSignature(FunctionSignature(parameterTypes: parameterTypes, returnType: returnType, valueParameterSymbols: [], valueParameterHasDefaultValues: [], valueParameterIsVararg: []), for: sym)
    }

    private func registerDigestMember(ownerSymbol: SymbolID, ownerType: TypeID, name: String, parameterTypes: [TypeID], returnType: TypeID, externalLinkName: String, symbols: SymbolTable, interner: StringInterner) {
        guard let ownerInfo = symbols.symbol(ownerSymbol) else { return }
        let fn = interner.intern(name)
        let fq = ownerInfo.fqName + [fn]
        guard symbols.lookupAll(fqName: fq).isEmpty else { return }
        let sym = symbols.define(kind: .function, name: fn, fqName: fq, declSite: nil, visibility: .public, flags: [.synthetic])
        symbols.setParentSymbol(ownerSymbol, for: sym)
        symbols.setExternalLinkName(externalLinkName, for: sym)
        symbols.setFunctionSignature(FunctionSignature(receiverType: ownerType, parameterTypes: parameterTypes, returnType: returnType, valueParameterSymbols: [], valueParameterHasDefaultValues: [], valueParameterIsVararg: []), for: sym)
    }
}
