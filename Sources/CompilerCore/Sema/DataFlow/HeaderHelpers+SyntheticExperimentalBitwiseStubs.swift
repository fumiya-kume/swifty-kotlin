import Foundation

extension DataFlowSemaPhase {
    func registerSyntheticExperimentalBitwiseStubs(
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner
    ) {
        let experimentalPkg = ensurePackage(
            path: ["kotlin", "experimental"],
            symbols: symbols,
            interner: interner
        )

        for name in ["and", "or", "xor"] {
            registerSyntheticExperimentalBitwiseFunction(
                named: name,
                receiverType: types.intType,
                parameters: [(name: "other", type: types.intType)],
                returnType: types.intType,
                packageFQName: experimentalPkg,
                symbols: symbols,
                interner: interner
            )
        }

        registerSyntheticExperimentalBitwiseFunction(
            named: "inv",
            receiverType: types.intType,
            parameters: [],
            returnType: types.intType,
            packageFQName: experimentalPkg,
            symbols: symbols,
            interner: interner
        )
    }

    private func registerSyntheticExperimentalBitwiseFunction(
        named name: String,
        receiverType: TypeID,
        parameters: [(name: String, type: TypeID)],
        returnType: TypeID,
        packageFQName: [InternedString],
        symbols: SymbolTable,
        interner: StringInterner
    ) {
        let functionName = interner.intern(name)
        let functionFQName = packageFQName + [functionName]
        if symbols.lookupAll(fqName: functionFQName).contains(where: { symbolID in
            guard let signature = symbols.functionSignature(for: symbolID) else {
                return false
            }
            return signature.receiverType == receiverType
                && signature.parameterTypes == parameters.map(\.type)
                && signature.returnType == returnType
        }) {
            return
        }

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

        var parameterSymbols: [SymbolID] = []
        for parameter in parameters {
            let parameterName = interner.intern(parameter.name)
            let parameterSymbol = symbols.define(
                kind: .valueParameter,
                name: parameterName,
                fqName: functionFQName + [parameterName],
                declSite: nil,
                visibility: .private,
                flags: [.synthetic]
            )
            symbols.setParentSymbol(functionSymbol, for: parameterSymbol)
            parameterSymbols.append(parameterSymbol)
        }

        symbols.setFunctionSignature(
            FunctionSignature(
                receiverType: receiverType,
                parameterTypes: parameters.map(\.type),
                returnType: returnType,
                isSuspend: false,
                valueParameterSymbols: parameterSymbols,
                valueParameterHasDefaultValues: Array(repeating: false, count: parameterSymbols.count),
                valueParameterIsVararg: Array(repeating: false, count: parameterSymbols.count)
            ),
            for: functionSymbol
        )
    }
}
