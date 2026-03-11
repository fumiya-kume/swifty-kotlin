import Foundation

// Synthetic stdlib top-level functions for kotlin.math (STDLIB-052).
// These stubs are intentionally minimal and only cover the math entry points
// currently needed by the compiler front-end and runtime.
extension DataFlowSemaPhase {
    func registerSyntheticMathStubs(
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner
    ) {
        let kotlinMathPkg = ensureSyntheticPackage(
            path: [interner.intern("kotlin"), interner.intern("math")],
            symbols: symbols
        )

        registerSyntheticMathTopLevelFunction(
            named: "abs",
            packageFQName: kotlinMathPkg,
            parameterName: "x",
            parameterType: types.intType,
            returnType: types.intType,
            externalLinkName: "kk_math_abs_int",
            symbols: symbols,
            interner: interner
        )

        registerSyntheticMathTopLevelFunction(
            named: "abs",
            packageFQName: kotlinMathPkg,
            parameterName: "x",
            parameterType: types.doubleType,
            returnType: types.doubleType,
            externalLinkName: "kk_math_abs",
            symbols: symbols,
            interner: interner
        )

        registerSyntheticMathTopLevelFunction(
            named: "sqrt",
            packageFQName: kotlinMathPkg,
            parameterName: "x",
            parameterType: types.doubleType,
            returnType: types.doubleType,
            externalLinkName: "kk_math_sqrt",
            symbols: symbols,
            interner: interner
        )

        registerSyntheticMathTopLevelFunction(
            named: "pow",
            packageFQName: kotlinMathPkg,
            parameters: [
                (name: "x", type: types.doubleType),
                (name: "y", type: types.doubleType),
            ],
            returnType: types.doubleType,
            externalLinkName: "kk_math_pow",
            symbols: symbols,
            interner: interner
        )

        registerSyntheticMathTopLevelFunction(
            named: "ceil",
            packageFQName: kotlinMathPkg,
            parameterName: "x",
            parameterType: types.doubleType,
            returnType: types.doubleType,
            externalLinkName: "kk_math_ceil",
            symbols: symbols,
            interner: interner
        )

        registerSyntheticMathTopLevelFunction(
            named: "floor",
            packageFQName: kotlinMathPkg,
            parameterName: "x",
            parameterType: types.doubleType,
            returnType: types.doubleType,
            externalLinkName: "kk_math_floor",
            symbols: symbols,
            interner: interner
        )

        registerSyntheticMathTopLevelFunction(
            named: "round",
            packageFQName: kotlinMathPkg,
            parameterName: "x",
            parameterType: types.doubleType,
            returnType: types.doubleType,
            externalLinkName: "kk_math_round",
            symbols: symbols,
            interner: interner
        )
    }

    private func registerSyntheticMathTopLevelFunction(
        named name: String,
        packageFQName: [InternedString],
        parameterName: String,
        parameterType: TypeID,
        returnType: TypeID,
        externalLinkName: String,
        symbols: SymbolTable,
        interner: StringInterner
    ) {
        registerSyntheticMathTopLevelFunction(
            named: name,
            packageFQName: packageFQName,
            parameters: [(name: parameterName, type: parameterType)],
            returnType: returnType,
            externalLinkName: externalLinkName,
            symbols: symbols,
            interner: interner
        )
    }

    private func registerSyntheticMathTopLevelFunction(
        named name: String,
        packageFQName: [InternedString],
        parameters: [(name: String, type: TypeID)],
        returnType: TypeID,
        externalLinkName: String,
        symbols: SymbolTable,
        interner: StringInterner
    ) {
        let functionName = interner.intern(name)
        let functionFQName = packageFQName + [functionName]
        if let existing = symbols.lookupAll(fqName: functionFQName).first(where: { symbolID in
            guard let existingSignature = symbols.functionSignature(for: symbolID) else {
                return false
            }
            return existingSignature.parameterTypes == parameters.map(\.type) &&
                existingSignature.returnType == returnType
        }) {
            symbols.setExternalLinkName(externalLinkName, for: existing)
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
        symbols.setExternalLinkName(externalLinkName, for: functionSymbol)

        var valueParameterSymbols: [SymbolID] = []
        for parameter in parameters {
            let paramNameID = interner.intern(parameter.name)
            let paramSymbol = symbols.define(
                kind: .valueParameter,
                name: paramNameID,
                fqName: functionFQName + [paramNameID],
                declSite: nil,
                visibility: .private,
                flags: [.synthetic]
            )
            symbols.setParentSymbol(functionSymbol, for: paramSymbol)
            valueParameterSymbols.append(paramSymbol)
        }

        symbols.setFunctionSignature(
            FunctionSignature(
                parameterTypes: parameters.map(\.type),
                returnType: returnType,
                isSuspend: false,
                valueParameterSymbols: valueParameterSymbols,
                valueParameterHasDefaultValues: Array(repeating: false, count: valueParameterSymbols.count),
                valueParameterIsVararg: Array(repeating: false, count: valueParameterSymbols.count)
            ),
            for: functionSymbol
        )
    }

    private func ensureSyntheticPackage(
        path: [InternedString],
        symbols: SymbolTable
    ) -> [InternedString] {
        var fqName: [InternedString] = []
        for part in path {
            let name = part
            fqName.append(name)
            if symbols.lookup(fqName: fqName) == nil {
                _ = symbols.define(
                    kind: .package,
                    name: name,
                    fqName: fqName,
                    declSite: nil,
                    visibility: .public,
                    flags: [.synthetic]
                )
            }
        }
        return fqName
    }
}
