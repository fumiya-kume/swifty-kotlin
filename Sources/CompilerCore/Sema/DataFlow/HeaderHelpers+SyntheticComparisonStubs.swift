import Foundation

extension DataFlowSemaPhase {
    func registerSyntheticComparisonStubs(
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner
    ) {
        let kotlinPkg: [InternedString] = [interner.intern("kotlin")]
        let comparisonsPkg: [InternedString] = kotlinPkg + [interner.intern("comparisons")]
        _ = ensureSyntheticPackage(fqName: kotlinPkg, symbols: symbols)
        let comparisonsPackageSymbol = ensureSyntheticPackage(fqName: comparisonsPkg, symbols: symbols)

        registerSyntheticIntComparisonFunction(
            named: "maxOf",
            packageFQName: comparisonsPkg,
            packageSymbol: comparisonsPackageSymbol,
            types: types,
            symbols: symbols,
            interner: interner
        )
        registerSyntheticIntComparisonFunction(
            named: "minOf",
            packageFQName: comparisonsPkg,
            packageSymbol: comparisonsPackageSymbol,
            types: types,
            symbols: symbols,
            interner: interner
        )
    }

    private func ensureSyntheticPackage(
        fqName: [InternedString],
        symbols: SymbolTable
    ) -> SymbolID {
        if let existing = symbols.lookup(fqName: fqName) {
            return existing
        }
        guard let name = fqName.last else {
            return .invalid
        }
        return symbols.define(
            kind: .package,
            name: name,
            fqName: fqName,
            declSite: nil,
            visibility: .public,
            flags: [.synthetic]
        )
    }

    private func registerSyntheticIntComparisonFunction(
        named name: String,
        packageFQName: [InternedString],
        packageSymbol: SymbolID,
        types: TypeSystem,
        symbols: SymbolTable,
        interner: StringInterner
    ) {
        let functionName = interner.intern(name)
        let functionFQName = packageFQName + [functionName]
        if symbols.lookupAll(fqName: functionFQName).contains(where: { symbolID in
            guard let signature = symbols.functionSignature(for: symbolID) else {
                return false
            }
            return signature.parameterTypes == [types.intType, types.intType]
                && signature.returnType == types.intType
        }) {
            return
        }

        let functionSymbol = symbols.define(
            kind: .function,
            name: functionName,
            fqName: functionFQName,
            declSite: nil,
            visibility: .public,
            flags: [.synthetic, .inlineFunction]
        )
        symbols.setParentSymbol(packageSymbol, for: functionSymbol)

        let aName = interner.intern("a")
        let bName = interner.intern("b")
        let aSymbol = symbols.define(
            kind: .valueParameter,
            name: aName,
            fqName: functionFQName + [aName],
            declSite: nil,
            visibility: .private,
            flags: [.synthetic]
        )
        let bSymbol = symbols.define(
            kind: .valueParameter,
            name: bName,
            fqName: functionFQName + [bName],
            declSite: nil,
            visibility: .private,
            flags: [.synthetic]
        )
        symbols.setParentSymbol(functionSymbol, for: aSymbol)
        symbols.setParentSymbol(functionSymbol, for: bSymbol)

        symbols.setFunctionSignature(
            FunctionSignature(
                parameterTypes: [types.intType, types.intType],
                returnType: types.intType,
                isSuspend: false,
                valueParameterSymbols: [aSymbol, bSymbol],
                valueParameterHasDefaultValues: [false, false],
                valueParameterIsVararg: [false, false]
            ),
            for: functionSymbol
        )
    }
}
