import Foundation

/// Synthetic stdlib top-level functions for kotlin.math (STDLIB-052).
/// These stubs are intentionally minimal and only cover the math entry points
/// currently needed by the compiler front-end and runtime.
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

        // STDLIB-500~509: Float overloads for trig/math functions
        let floatType = types.floatType

        for (name, linkName) in [
            ("sin", "kk_math_sin_float"), ("cos", "kk_math_cos_float"),
            ("tan", "kk_math_tan_float"), ("asin", "kk_math_asin_float"),
            ("acos", "kk_math_acos_float"), ("atan", "kk_math_atan_float"),
            ("sqrt", "kk_math_sqrt_float"), ("round", "kk_math_round_float"),
            ("ceil", "kk_math_ceil_float"), ("floor", "kk_math_floor_float"),
            ("abs", "kk_math_abs_float"),
            ("exp", "kk_math_exp_float"), ("ln", "kk_math_ln_float"),
            ("log2", "kk_math_log2_float"), ("log10", "kk_math_log10_float"),
            ("sign", "kk_math_sign_float"),
        ] {
            registerSyntheticMathTopLevelFunction(
                named: name,
                packageFQName: kotlinMathPkg,
                parameterName: "x",
                parameterType: floatType,
                returnType: floatType,
                externalLinkName: linkName,
                symbols: symbols,
                interner: interner
            )
        }

        registerSyntheticMathTopLevelFunction(
            named: "atan2",
            packageFQName: kotlinMathPkg,
            parameters: [
                (name: "y", type: floatType),
                (name: "x", type: floatType),
            ],
            returnType: floatType,
            externalLinkName: "kk_math_atan2_float",
            symbols: symbols,
            interner: interner
        )

        registerSyntheticMathTopLevelFunction(
            named: "log",
            packageFQName: kotlinMathPkg,
            parameters: [
                (name: "x", type: floatType),
                (name: "base", type: floatType),
            ],
            returnType: floatType,
            externalLinkName: "kk_math_log_float",
            symbols: symbols,
            interner: interner
        )

        registerSyntheticMathTopLevelFunction(
            named: "hypot",
            packageFQName: kotlinMathPkg,
            parameters: [
                (name: "x", type: floatType),
                (name: "y", type: floatType),
            ],
            returnType: floatType,
            externalLinkName: "kk_math_hypot_float",
            symbols: symbols,
            interner: interner
        )

        // STDLIB-510~511: roundToInt / roundToLong extension functions
        registerSyntheticMathTopLevelFunction(
            named: "roundToInt",
            packageFQName: kotlinMathPkg,
            parameterName: "x",
            parameterType: floatType,
            returnType: types.intType,
            externalLinkName: "kk_float_roundToInt",
            symbols: symbols,
            interner: interner
        )
        registerSyntheticMathTopLevelFunction(
            named: "roundToInt",
            packageFQName: kotlinMathPkg,
            parameterName: "x",
            parameterType: types.doubleType,
            returnType: types.intType,
            externalLinkName: "kk_double_roundToInt",
            symbols: symbols,
            interner: interner
        )
        registerSyntheticMathTopLevelFunction(
            named: "roundToLong",
            packageFQName: kotlinMathPkg,
            parameterName: "x",
            parameterType: floatType,
            returnType: types.longType,
            externalLinkName: "kk_float_roundToLong",
            symbols: symbols,
            interner: interner
        )
        registerSyntheticMathTopLevelFunction(
            named: "roundToLong",
            packageFQName: kotlinMathPkg,
            parameterName: "x",
            parameterType: types.doubleType,
            returnType: types.longType,
            externalLinkName: "kk_double_roundToLong",
            symbols: symbols,
            interner: interner
        )

        // STDLIB-512~513: ulp / nextUp / nextDown extension properties
        registerSyntheticMathTopLevelFunction(
            named: "ulp",
            packageFQName: kotlinMathPkg,
            parameterName: "x",
            parameterType: types.doubleType,
            returnType: types.doubleType,
            externalLinkName: "kk_double_ulp",
            symbols: symbols,
            interner: interner
        )
        registerSyntheticMathTopLevelFunction(
            named: "nextUp",
            packageFQName: kotlinMathPkg,
            parameterName: "x",
            parameterType: types.doubleType,
            returnType: types.doubleType,
            externalLinkName: "kk_double_nextUp",
            symbols: symbols,
            interner: interner
        )
        registerSyntheticMathTopLevelFunction(
            named: "nextDown",
            packageFQName: kotlinMathPkg,
            parameterName: "x",
            parameterType: types.doubleType,
            returnType: types.doubleType,
            externalLinkName: "kk_double_nextDown",
            symbols: symbols,
            interner: interner
        )
        registerSyntheticMathTopLevelFunction(
            named: "ulp",
            packageFQName: kotlinMathPkg,
            parameterName: "x",
            parameterType: floatType,
            returnType: floatType,
            externalLinkName: "kk_float_ulp",
            symbols: symbols,
            interner: interner
        )
        registerSyntheticMathTopLevelFunction(
            named: "nextUp",
            packageFQName: kotlinMathPkg,
            parameterName: "x",
            parameterType: floatType,
            returnType: floatType,
            externalLinkName: "kk_float_nextUp",
            symbols: symbols,
            interner: interner
        )
        registerSyntheticMathTopLevelFunction(
            named: "nextDown",
            packageFQName: kotlinMathPkg,
            parameterName: "x",
            parameterType: floatType,
            returnType: floatType,
            externalLinkName: "kk_float_nextDown",
            symbols: symbols,
            interner: interner
        )

        // Trigonometric functions (STDLIB-430) — Double variants
        registerSyntheticMathTopLevelFunction(
            named: "sin",
            packageFQName: kotlinMathPkg,
            parameterName: "x",
            parameterType: types.doubleType,
            returnType: types.doubleType,
            externalLinkName: "kk_math_sin",
            symbols: symbols,
            interner: interner
        )

        registerSyntheticMathTopLevelFunction(
            named: "cos",
            packageFQName: kotlinMathPkg,
            parameterName: "x",
            parameterType: types.doubleType,
            returnType: types.doubleType,
            externalLinkName: "kk_math_cos",
            symbols: symbols,
            interner: interner
        )

        registerSyntheticMathTopLevelFunction(
            named: "tan",
            packageFQName: kotlinMathPkg,
            parameterName: "x",
            parameterType: types.doubleType,
            returnType: types.doubleType,
            externalLinkName: "kk_math_tan",
            symbols: symbols,
            interner: interner
        )

        registerSyntheticMathTopLevelFunction(
            named: "asin",
            packageFQName: kotlinMathPkg,
            parameterName: "x",
            parameterType: types.doubleType,
            returnType: types.doubleType,
            externalLinkName: "kk_math_asin",
            symbols: symbols,
            interner: interner
        )

        registerSyntheticMathTopLevelFunction(
            named: "acos",
            packageFQName: kotlinMathPkg,
            parameterName: "x",
            parameterType: types.doubleType,
            returnType: types.doubleType,
            externalLinkName: "kk_math_acos",
            symbols: symbols,
            interner: interner
        )

        registerSyntheticMathTopLevelFunction(
            named: "atan",
            packageFQName: kotlinMathPkg,
            parameterName: "x",
            parameterType: types.doubleType,
            returnType: types.doubleType,
            externalLinkName: "kk_math_atan",
            symbols: symbols,
            interner: interner
        )

        registerSyntheticMathTopLevelFunction(
            named: "atan2",
            packageFQName: kotlinMathPkg,
            parameters: [
                (name: "y", type: types.doubleType),
                (name: "x", type: types.doubleType),
            ],
            returnType: types.doubleType,
            externalLinkName: "kk_math_atan2",
            symbols: symbols,
            interner: interner
        )

        // STDLIB-431: exp/ln/log functions

        registerSyntheticMathTopLevelFunction(
            named: "exp",
            packageFQName: kotlinMathPkg,
            parameterName: "x",
            parameterType: types.doubleType,
            returnType: types.doubleType,
            externalLinkName: "kk_math_exp",
            symbols: symbols,
            interner: interner
        )

        registerSyntheticMathTopLevelFunction(
            named: "ln",
            packageFQName: kotlinMathPkg,
            parameterName: "x",
            parameterType: types.doubleType,
            returnType: types.doubleType,
            externalLinkName: "kk_math_ln",
            symbols: symbols,
            interner: interner
        )

        registerSyntheticMathTopLevelFunction(
            named: "log2",
            packageFQName: kotlinMathPkg,
            parameterName: "x",
            parameterType: types.doubleType,
            returnType: types.doubleType,
            externalLinkName: "kk_math_log2",
            symbols: symbols,
            interner: interner
        )

        registerSyntheticMathTopLevelFunction(
            named: "log10",
            packageFQName: kotlinMathPkg,
            parameterName: "x",
            parameterType: types.doubleType,
            returnType: types.doubleType,
            externalLinkName: "kk_math_log10",
            symbols: symbols,
            interner: interner
        )

        registerSyntheticMathTopLevelFunction(
            named: "log",
            packageFQName: kotlinMathPkg,
            parameters: [
                (name: "x", type: types.doubleType),
                (name: "base", type: types.doubleType),
            ],
            returnType: types.doubleType,
            externalLinkName: "kk_math_log",
            symbols: symbols,
            interner: interner
        )

        // STDLIB-432: sign/hypot + PI/E constants

        registerSyntheticMathTopLevelFunction(
            named: "sign",
            packageFQName: kotlinMathPkg,
            parameterName: "x",
            parameterType: types.doubleType,
            returnType: types.doubleType,
            externalLinkName: "kk_math_sign",
            symbols: symbols,
            interner: interner
        )

        registerSyntheticMathTopLevelFunction(
            named: "hypot",
            packageFQName: kotlinMathPkg,
            parameters: [
                (name: "x", type: types.doubleType),
                (name: "y", type: types.doubleType),
            ],
            returnType: types.doubleType,
            externalLinkName: "kk_math_hypot",
            symbols: symbols,
            interner: interner
        )

        registerSyntheticMathTopLevelFunction(
            named: "PI",
            packageFQName: kotlinMathPkg,
            parameters: [],
            returnType: types.doubleType,
            externalLinkName: "kk_math_PI",
            symbols: symbols,
            interner: interner
        )

        registerSyntheticMathTopLevelFunction(
            named: "E",
            packageFQName: kotlinMathPkg,
            parameters: [],
            returnType: types.doubleType,
            externalLinkName: "kk_math_E",
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
