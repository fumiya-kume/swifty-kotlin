import Foundation

/// Synthetic Kotlin/JS `js` external function surface.
extension DataFlowSemaPhase {
    func registerSyntheticJsFunctionStubs(
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner
    ) {
        let kotlinJsPkg = ensurePackage(
            path: ["kotlin", "js"],
            symbols: symbols,
            interner: interner
        )
        registerSyntheticJsFunction(
            packageFQName: kotlinJsPkg,
            parameterTypes: [types.stringType],
            returnType: types.anyType,
            symbols: symbols,
            interner: interner
        )
    }

    private func registerSyntheticJsFunction(
        packageFQName: [InternedString],
        parameterTypes: [TypeID],
        returnType: TypeID,
        symbols: SymbolTable,
        interner: StringInterner
    ) {
        let functionName = interner.intern("js")
        let functionFQName = packageFQName + [functionName]
        let alreadyRegistered = symbols.lookupAll(fqName: functionFQName).contains { symbolID in
            guard let signature = symbols.functionSignature(for: symbolID) else {
                return false
            }
            return signature.parameterTypes == parameterTypes
                && signature.returnType == returnType
        }
        guard !alreadyRegistered else { return }

        let functionSymbol = symbols.define(
            kind: .function,
            name: functionName,
            fqName: functionFQName,
            declSite: nil,
            visibility: .public,
            flags: [.synthetic]
        )
        if let packageSymbol = symbols.lookup(fqName: packageFQName) {
            symbols.setParentSymbol(packageSymbol, for: functionSymbol)
        }

        let parameterName = interner.intern("code")
        let parameterSymbol = symbols.define(
            kind: .valueParameter,
            name: parameterName,
            fqName: functionFQName + [parameterName],
            declSite: nil,
            visibility: .private,
            flags: [.synthetic]
        )
        symbols.setParentSymbol(functionSymbol, for: parameterSymbol)
        symbols.setPropertyType(parameterTypes[0], for: parameterSymbol)

        symbols.setFunctionSignature(
            FunctionSignature(
                parameterTypes: parameterTypes,
                returnType: returnType,
                isSuspend: false,
                valueParameterSymbols: [parameterSymbol],
                valueParameterHasDefaultValues: [false],
                valueParameterIsVararg: [false]
            ),
            for: functionSymbol
        )
    }
}
