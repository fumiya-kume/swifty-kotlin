extension DataFlowSemaPhase {
    func registerSyntheticKotlinVersionStubs(
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner
    ) {
        let kotlinPkg = ensurePackage(path: ["kotlin"], symbols: symbols, interner: interner)
        let classSymbol = ensureClassSymbol(
            named: "KotlinVersion",
            in: kotlinPkg,
            symbols: symbols,
            interner: interner
        )
        if let kotlinPkgSymbol = symbols.lookup(fqName: kotlinPkg) {
            symbols.setParentSymbol(kotlinPkgSymbol, for: classSymbol)
        }

        let classType = types.make(.classType(ClassType(
            classSymbol: classSymbol,
            args: [],
            nullability: .nonNull
        )))

        registerKotlinVersionConstructor(
            ownerSymbol: classSymbol,
            ownerType: classType,
            parameters: [
                ("major", types.intType),
                ("minor", types.intType),
            ],
            externalLinkName: "kk_kotlin_version_new",
            symbols: symbols,
            interner: interner
        )
        registerKotlinVersionConstructor(
            ownerSymbol: classSymbol,
            ownerType: classType,
            parameters: [
                ("major", types.intType),
                ("minor", types.intType),
                ("patch", types.intType),
            ],
            externalLinkName: "kk_kotlin_version_new_patch",
            symbols: symbols,
            interner: interner
        )

        registerKotlinVersionProperty(
            named: "major",
            externalLinkName: "kk_kotlin_version_major",
            ownerSymbol: classSymbol,
            returnType: types.intType,
            symbols: symbols,
            interner: interner
        )
        registerKotlinVersionProperty(
            named: "minor",
            externalLinkName: "kk_kotlin_version_minor",
            ownerSymbol: classSymbol,
            returnType: types.intType,
            symbols: symbols,
            interner: interner
        )
        registerKotlinVersionProperty(
            named: "patch",
            externalLinkName: "kk_kotlin_version_patch",
            ownerSymbol: classSymbol,
            returnType: types.intType,
            symbols: symbols,
            interner: interner
        )
    }

    private func registerKotlinVersionConstructor(
        ownerSymbol: SymbolID,
        ownerType: TypeID,
        parameters: [(name: String, type: TypeID)],
        externalLinkName: String,
        symbols: SymbolTable,
        interner: StringInterner
    ) {
        guard let ownerInfo = symbols.symbol(ownerSymbol) else {
            return
        }
        let initName = interner.intern("<init>")
        let constructorFQName = ownerInfo.fqName + [initName]
        let parameterTypes = parameters.map(\.type)
        let existing = symbols.lookupAll(fqName: constructorFQName).contains { symbolID in
            guard symbols.symbol(symbolID)?.kind == .constructor,
                  let signature = symbols.functionSignature(for: symbolID)
            else {
                return false
            }
            return signature.parameterTypes == parameterTypes
        }
        guard !existing else {
            return
        }

        let constructorSymbol = symbols.define(
            kind: .constructor,
            name: initName,
            fqName: constructorFQName,
            declSite: nil,
            visibility: .public,
            flags: [.synthetic]
        )
        symbols.setParentSymbol(ownerSymbol, for: constructorSymbol)
        symbols.setExternalLinkName(externalLinkName, for: constructorSymbol)

        let valueParameterSymbols = parameters.map { parameter in
            let parameterName = interner.intern(parameter.name)
            let parameterSymbol = symbols.define(
                kind: .valueParameter,
                name: parameterName,
                fqName: constructorFQName + [parameterName],
                declSite: nil,
                visibility: .private,
                flags: [.synthetic]
            )
            symbols.setParentSymbol(constructorSymbol, for: parameterSymbol)
            symbols.setPropertyType(parameter.type, for: parameterSymbol)
            return parameterSymbol
        }

        symbols.setFunctionSignature(
            FunctionSignature(
                parameterTypes: parameterTypes,
                returnType: ownerType,
                valueParameterSymbols: valueParameterSymbols,
                valueParameterHasDefaultValues: Array(repeating: false, count: valueParameterSymbols.count),
                valueParameterIsVararg: Array(repeating: false, count: valueParameterSymbols.count)
            ),
            for: constructorSymbol
        )
    }

    private func registerKotlinVersionProperty(
        named name: String,
        externalLinkName: String,
        ownerSymbol: SymbolID,
        returnType: TypeID,
        symbols: SymbolTable,
        interner: StringInterner
    ) {
        guard let ownerInfo = symbols.symbol(ownerSymbol) else {
            return
        }
        let propertyName = interner.intern(name)
        let propertyFQName = ownerInfo.fqName + [propertyName]
        if let existing = symbols.lookupAll(fqName: propertyFQName).first(where: { symbolID in
            symbols.symbol(symbolID)?.kind == .property
        }) {
            symbols.setPropertyType(returnType, for: existing)
            symbols.setExternalLinkName(externalLinkName, for: existing)
            return
        }

        let propertySymbol = symbols.define(
            kind: .property,
            name: propertyName,
            fqName: propertyFQName,
            declSite: nil,
            visibility: .public,
            flags: [.synthetic]
        )
        symbols.setParentSymbol(ownerSymbol, for: propertySymbol)
        symbols.setPropertyType(returnType, for: propertySymbol)
        symbols.setExternalLinkName(externalLinkName, for: propertySymbol)
    }
}
