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

        let remainingFloatingMemberOverloads: [(name: String, parameters: [(name: String, type: TypeID)], returnType: TypeID, linkName: String)] = [
            ("IEEErem", [(name: "x", type: types.doubleType), (name: "divisor", type: types.doubleType)], types.doubleType, "kk_math_IEEErem"),
            ("IEEErem", [(name: "x", type: types.floatType), (name: "divisor", type: types.floatType)], types.floatType, "kk_math_IEEErem_float"),
            ("nextTowards", [(name: "x", type: types.doubleType), (name: "to", type: types.doubleType)], types.doubleType, "kk_math_nextTowards"),
            ("nextTowards", [(name: "x", type: types.floatType), (name: "to", type: types.floatType)], types.floatType, "kk_math_nextTowards_float"),
            ("pow", [(name: "x", type: types.floatType), (name: "y", type: types.floatType)], types.floatType, "kk_math_pow_float"),
            ("pow", [(name: "x", type: types.doubleType), (name: "n", type: types.intType)], types.doubleType, "kk_math_pow_int"),
            ("pow", [(name: "x", type: types.floatType), (name: "n", type: types.intType)], types.floatType, "kk_math_pow_float_int"),
            ("withSign", [(name: "x", type: types.doubleType), (name: "sign", type: types.doubleType)], types.doubleType, "kk_math_withSign"),
            ("withSign", [(name: "x", type: types.doubleType), (name: "sign", type: types.intType)], types.doubleType, "kk_math_withSign_int"),
            ("withSign", [(name: "x", type: types.floatType), (name: "sign", type: types.floatType)], types.floatType, "kk_math_withSign_float"),
            ("withSign", [(name: "x", type: types.floatType), (name: "sign", type: types.intType)], types.floatType, "kk_math_withSign_float_int"),
        ]
        for overload in remainingFloatingMemberOverloads {
            registerSyntheticMathTopLevelFunction(
                named: overload.name,
                packageFQName: kotlinMathPkg,
                parameters: overload.parameters,
                returnType: overload.returnType,
                externalLinkName: overload.linkName,
                symbols: symbols,
                interner: interner
            )
            if let receiverParameter = overload.parameters.first {
                registerSyntheticMathExtensionFunction(
                    named: overload.name,
                    packageFQName: kotlinMathPkg,
                    receiverType: receiverParameter.type,
                    parameters: Array(overload.parameters.dropFirst()),
                    returnType: overload.returnType,
                    externalLinkName: overload.linkName,
                    symbols: symbols,
                    interner: interner
                )
            }
        }

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
            ("expm1", "kk_math_expm1_float"), ("ln1p", "kk_math_ln1p_float"),
            ("log2", "kk_math_log2_float"), ("log10", "kk_math_log10_float"),
            ("sign", "kk_math_sign_float"),
            // STDLIB-MATH-109: Hyperbolic and cbrt Float overloads
            ("sinh", "kk_math_sinh_float"), ("cosh", "kk_math_cosh_float"),
            ("tanh", "kk_math_tanh_float"), ("cbrt", "kk_math_cbrt_float"),
            // STDLIB-MATH-113: Inverse hyperbolic Float overloads
            ("acosh", "kk_math_acosh_float"), ("asinh", "kk_math_asinh_float"),
            ("atanh", "kk_math_atanh_float"),
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

        // STDLIB-514: abs(Long), truncate

        registerSyntheticMathTopLevelFunction(
            named: "abs",
            packageFQName: kotlinMathPkg,
            parameterName: "n",
            parameterType: types.longType,
            returnType: types.longType,
            externalLinkName: "kk_math_abs_long",
            symbols: symbols,
            interner: interner
        )

        registerSyntheticMathTopLevelFunction(
            named: "truncate",
            packageFQName: kotlinMathPkg,
            parameterName: "x",
            parameterType: types.doubleType,
            returnType: types.doubleType,
            externalLinkName: "kk_math_truncate",
            symbols: symbols,
            interner: interner
        )

        registerSyntheticMathTopLevelFunction(
            named: "truncate",
            packageFQName: kotlinMathPkg,
            parameterName: "x",
            parameterType: floatType,
            returnType: floatType,
            externalLinkName: "kk_math_truncate_float",
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
            named: "expm1",
            packageFQName: kotlinMathPkg,
            parameterName: "x",
            parameterType: types.doubleType,
            returnType: types.doubleType,
            externalLinkName: "kk_math_expm1",
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
            named: "ln1p",
            packageFQName: kotlinMathPkg,
            parameterName: "x",
            parameterType: types.doubleType,
            returnType: types.doubleType,
            externalLinkName: "kk_math_ln1p",
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

        // STDLIB-MATH-109: Hyperbolic functions and cbrt (Double)
        registerSyntheticMathTopLevelFunction(
            named: "sinh",
            packageFQName: kotlinMathPkg,
            parameterName: "x",
            parameterType: types.doubleType,
            returnType: types.doubleType,
            externalLinkName: "kk_math_sinh",
            symbols: symbols,
            interner: interner
        )
        registerSyntheticMathTopLevelFunction(
            named: "cosh",
            packageFQName: kotlinMathPkg,
            parameterName: "x",
            parameterType: types.doubleType,
            returnType: types.doubleType,
            externalLinkName: "kk_math_cosh",
            symbols: symbols,
            interner: interner
        )
        registerSyntheticMathTopLevelFunction(
            named: "tanh",
            packageFQName: kotlinMathPkg,
            parameterName: "x",
            parameterType: types.doubleType,
            returnType: types.doubleType,
            externalLinkName: "kk_math_tanh",
            symbols: symbols,
            interner: interner
        )
        registerSyntheticMathTopLevelFunction(
            named: "cbrt",
            packageFQName: kotlinMathPkg,
            parameterName: "x",
            parameterType: types.doubleType,
            returnType: types.doubleType,
            externalLinkName: "kk_math_cbrt",
            symbols: symbols,
            interner: interner
        )

        // STDLIB-MATH-113: Inverse hyperbolic functions (Double)
        registerSyntheticMathTopLevelFunction(
            named: "acosh",
            packageFQName: kotlinMathPkg,
            parameterName: "x",
            parameterType: types.doubleType,
            returnType: types.doubleType,
            externalLinkName: "kk_math_acosh",
            symbols: symbols,
            interner: interner
        )
        registerSyntheticMathTopLevelFunction(
            named: "asinh",
            packageFQName: kotlinMathPkg,
            parameterName: "x",
            parameterType: types.doubleType,
            returnType: types.doubleType,
            externalLinkName: "kk_math_asinh",
            symbols: symbols,
            interner: interner
        )
        registerSyntheticMathTopLevelFunction(
            named: "atanh",
            packageFQName: kotlinMathPkg,
            parameterName: "x",
            parameterType: types.doubleType,
            returnType: types.doubleType,
            externalLinkName: "kk_math_atanh",
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

        // STDLIB-MATH-006: max/min overload matrix.
        let minMaxOverloads: [(name: String, type: TypeID, linkName: String)] = [
            ("max", types.doubleType, "kk_math_max"),
            ("max", floatType, "kk_math_max_float"),
            ("max", types.intType, "kk_math_max_int"),
            ("max", types.longType, "kk_math_max_long"),
            ("max", types.uintType, "kk_math_max_uint"),
            ("max", types.ulongType, "kk_math_max_ulong"),
            ("min", types.doubleType, "kk_math_min"),
            ("min", floatType, "kk_math_min_float"),
            ("min", types.intType, "kk_math_min_int"),
            ("min", types.longType, "kk_math_min_long"),
            ("min", types.uintType, "kk_math_min_uint"),
            ("min", types.ulongType, "kk_math_min_ulong"),
        ]
        for overload in minMaxOverloads {
            registerSyntheticMathTopLevelFunction(
                named: overload.name,
                packageFQName: kotlinMathPkg,
                parameters: [
                    (name: "a", type: overload.type),
                    (name: "b", type: overload.type),
                ],
                returnType: overload.type,
                externalLinkName: overload.linkName,
                symbols: symbols,
                interner: interner
            )
        }

        registerSyntheticMathTopLevelProperty(
            named: "PI",
            packageFQName: kotlinMathPkg,
            returnType: types.doubleType,
            externalLinkName: "kk_math_PI",
            symbols: symbols,
            interner: interner
        )

        registerSyntheticMathTopLevelProperty(
            named: "E",
            packageFQName: kotlinMathPkg,
            returnType: types.doubleType,
            externalLinkName: "kk_math_E",
            symbols: symbols,
            interner: interner
        )

        // STDLIB-MATH-004: official kotlin.math extension property surface.
        for property in [
            (name: "absoluteValue", receiverType: types.doubleType, returnType: types.doubleType, linkName: "kk_math_abs"),
            (name: "absoluteValue", receiverType: floatType, returnType: floatType, linkName: "kk_math_abs_float"),
            (name: "absoluteValue", receiverType: types.intType, returnType: types.intType, linkName: "kk_math_abs_int"),
            (name: "absoluteValue", receiverType: types.longType, returnType: types.longType, linkName: "kk_math_abs_long"),
            (name: "sign", receiverType: types.doubleType, returnType: types.doubleType, linkName: "kk_math_sign"),
            (name: "sign", receiverType: floatType, returnType: floatType, linkName: "kk_math_sign_float"),
            (name: "sign", receiverType: types.intType, returnType: types.intType, linkName: "kk_math_sign_int"),
            (name: "sign", receiverType: types.longType, returnType: types.intType, linkName: "kk_math_sign_long"),
            (name: "ulp", receiverType: types.doubleType, returnType: types.doubleType, linkName: "kk_double_ulp"),
            (name: "ulp", receiverType: floatType, returnType: floatType, linkName: "kk_float_ulp"),
        ] {
            registerSyntheticMathExtensionProperty(
                named: property.name,
                packageFQName: kotlinMathPkg,
                receiverType: property.receiverType,
                returnType: property.returnType,
                externalLinkName: property.linkName,
                symbols: symbols,
                interner: interner
            )
        }

        // STDLIB-111: IEEE 754 rounding modes — Double convenience entry points
        for (name, linkName) in [
            ("roundUp", "kk_math_round_up"),
            ("roundDown", "kk_math_round_down"),
            ("roundCeiling", "kk_math_round_ceiling"),
            ("roundFloor", "kk_math_round_floor"),
            ("roundHalfUp", "kk_math_round_half_up"),
            ("roundHalfDown", "kk_math_round_half_down"),
            ("roundHalfEven", "kk_math_round_half_even"),
            ("roundUnnecessary", "kk_math_round_unnecessary"),
        ] {
            registerSyntheticMathTopLevelFunction(
                named: name,
                packageFQName: kotlinMathPkg,
                parameterName: "x",
                parameterType: types.doubleType,
                returnType: types.doubleType,
                externalLinkName: linkName,
                symbols: symbols,
                interner: interner
            )
        }

        // STDLIB-111: IEEE 754 rounding modes — Float convenience entry points
        for (name, linkName) in [
            ("roundUp", "kk_math_round_up_float"),
            ("roundDown", "kk_math_round_down_float"),
            ("roundCeiling", "kk_math_round_ceiling_float"),
            ("roundFloor", "kk_math_round_floor_float"),
            ("roundHalfUp", "kk_math_round_half_up_float"),
            ("roundHalfDown", "kk_math_round_half_down_float"),
            ("roundHalfEven", "kk_math_round_half_even_float"),
            ("roundUnnecessary", "kk_math_round_unnecessary_float"),
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

    private func registerSyntheticMathExtensionFunction(
        named name: String,
        packageFQName: [InternedString],
        receiverType: TypeID,
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
            return existingSignature.receiverType == receiverType &&
                existingSignature.parameterTypes == parameters.map(\.type) &&
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
                receiverType: receiverType,
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

    private func registerSyntheticMathTopLevelProperty(
        named name: String,
        packageFQName: [InternedString],
        returnType: TypeID,
        externalLinkName: String,
        symbols: SymbolTable,
        interner: StringInterner
    ) {
        let propertyName = interner.intern(name)
        let propertyFQName = packageFQName + [propertyName]
        if let existing = symbols.lookupAll(fqName: propertyFQName).first(where: { symbolID in
            symbols.symbol(symbolID)?.kind == .property
        }) {
            symbols.setExternalLinkName(externalLinkName, for: existing)
            symbols.setPropertyType(returnType, for: existing)
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
        if let packageSymbol = symbols.lookup(fqName: packageFQName) {
            symbols.setParentSymbol(packageSymbol, for: propertySymbol)
        }
        symbols.setExternalLinkName(externalLinkName, for: propertySymbol)
        symbols.setPropertyType(returnType, for: propertySymbol)
    }

    private func registerSyntheticMathExtensionProperty(
        named name: String,
        packageFQName: [InternedString],
        receiverType: TypeID,
        returnType: TypeID,
        externalLinkName: String,
        symbols: SymbolTable,
        interner: StringInterner
    ) {
        let propertyName = interner.intern(name)
        let propertyFQName = packageFQName + [propertyName]
        if let existing = symbols.lookupAll(fqName: propertyFQName).first(where: { symbolID in
            symbols.symbol(symbolID)?.kind == .property
                && symbols.extensionPropertyReceiverType(for: symbolID) == receiverType
        }) {
            symbols.setExternalLinkName(externalLinkName, for: existing)
            symbols.setPropertyType(returnType, for: existing)
            if let getterSymbol = symbols.extensionPropertyGetterAccessor(for: existing) {
                symbols.setFunctionSignature(
                    FunctionSignature(
                        receiverType: receiverType,
                        parameterTypes: [],
                        returnType: returnType
                    ),
                    for: getterSymbol
                )
                symbols.setExternalLinkName(externalLinkName, for: getterSymbol)
            }
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
        if let packageSymbol = symbols.lookup(fqName: packageFQName) {
            symbols.setParentSymbol(packageSymbol, for: propertySymbol)
        }
        symbols.setPropertyType(returnType, for: propertySymbol)
        symbols.setExtensionPropertyReceiverType(receiverType, for: propertySymbol)
        symbols.setExternalLinkName(externalLinkName, for: propertySymbol)

        let getterName = interner.intern("get")
        let getterSymbol = symbols.define(
            kind: .function,
            name: getterName,
            fqName: propertyFQName + [interner.intern("$get")],
            declSite: nil,
            visibility: .public,
            flags: [.synthetic]
        )
        symbols.setParentSymbol(propertySymbol, for: getterSymbol)
        symbols.setFunctionSignature(
            FunctionSignature(
                receiverType: receiverType,
                parameterTypes: [],
                returnType: returnType
            ),
            for: getterSymbol
        )
        symbols.setExtensionPropertyGetterAccessor(getterSymbol, for: propertySymbol)
        symbols.setAccessorOwnerProperty(propertySymbol, for: getterSymbol)
        symbols.setExternalLinkName(externalLinkName, for: getterSymbol)
    }
}
