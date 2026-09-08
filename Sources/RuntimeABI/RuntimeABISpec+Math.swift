// Math functions (STDLIB-052).

public extension RuntimeABISpec {
    static let mathFunctions: [RuntimeABIFunctionSpec] = [
        RuntimeABIFunctionSpec(
            name: "__kk_math_sqrt",
            parameters: [
                RuntimeABIParameter(name: "value", type: .intptr),
            ],
            returnType: .intptr,
            section: "Math",
            isThrowing: false
        ),
        RuntimeABIFunctionSpec(
            name: "__kk_math_pow",
            parameters: [
                RuntimeABIParameter(name: "base", type: .intptr),
                RuntimeABIParameter(name: "exp", type: .intptr),
            ],
            returnType: .intptr,
            section: "Math",
            isThrowing: false
        ),
        // STDLIB-MATH-007: remaining official floating-point overloads.
        RuntimeABIFunctionSpec(
            name: "__kk_math_pow_float",
            parameters: [
                RuntimeABIParameter(name: "base", type: .intptr),
                RuntimeABIParameter(name: "exp", type: .intptr),
            ],
            returnType: .intptr,
            section: "Math",
            isThrowing: false
        ),
        RuntimeABIFunctionSpec(
            name: "__kk_math_pow_int",
            parameters: [
                RuntimeABIParameter(name: "base", type: .intptr),
                RuntimeABIParameter(name: "exp", type: .intptr),
            ],
            returnType: .intptr,
            section: "Math",
            isThrowing: false
        ),
        RuntimeABIFunctionSpec(
            name: "__kk_math_pow_float_int",
            parameters: [
                RuntimeABIParameter(name: "base", type: .intptr),
                RuntimeABIParameter(name: "exp", type: .intptr),
            ],
            returnType: .intptr,
            section: "Math",
            isThrowing: false
        ),
        RuntimeABIFunctionSpec(
            name: "__kk_math_IEEErem",
            parameters: [
                RuntimeABIParameter(name: "x", type: .intptr),
                RuntimeABIParameter(name: "y", type: .intptr),
            ],
            returnType: .intptr,
            section: "Math",
            isThrowing: false
        ),
        RuntimeABIFunctionSpec(
            name: "__kk_math_IEEErem_float",
            parameters: [
                RuntimeABIParameter(name: "x", type: .intptr),
                RuntimeABIParameter(name: "y", type: .intptr),
            ],
            returnType: .intptr,
            section: "Math",
            isThrowing: false
        ),
        RuntimeABIFunctionSpec(
            name: "__kk_math_nextTowards",
            parameters: [
                RuntimeABIParameter(name: "from", type: .intptr),
                RuntimeABIParameter(name: "to", type: .intptr),
            ],
            returnType: .intptr,
            section: "Math",
            isThrowing: false
        ),
        RuntimeABIFunctionSpec(
            name: "__kk_math_nextTowards_float",
            parameters: [
                RuntimeABIParameter(name: "from", type: .intptr),
                RuntimeABIParameter(name: "to", type: .intptr),
            ],
            returnType: .intptr,
            section: "Math",
            isThrowing: false
        ),
        RuntimeABIFunctionSpec(
            name: "__kk_math_ceil",
            parameters: [
                RuntimeABIParameter(name: "value", type: .intptr),
            ],
            returnType: .intptr,
            section: "Math",
            isThrowing: false
        ),
        RuntimeABIFunctionSpec(
            name: "__kk_math_floor",
            parameters: [
                RuntimeABIParameter(name: "value", type: .intptr),
            ],
            returnType: .intptr,
            section: "Math",
            isThrowing: false
        ),
        RuntimeABIFunctionSpec(
            name: "__kk_math_round",
            parameters: [
                RuntimeABIParameter(name: "value", type: .intptr),
            ],
            returnType: .intptr,
            section: "Math",
            isThrowing: false
        ),
        // Trigonometric functions (STDLIB-430)
        // Note: Each trig entry is spelled out individually rather than generated
        // programmatically. This repetition is intentional — the ABI spec must be
        // a plain, auditable list so that any ABI-breaking change is visible in
        // code review as a concrete diff, not hidden behind abstraction.
        RuntimeABIFunctionSpec(
            name: "__kk_math_sin",
            parameters: [
                RuntimeABIParameter(name: "value", type: .intptr),
            ],
            returnType: .intptr,
            section: "Math",
            isThrowing: false
        ),
        RuntimeABIFunctionSpec(
            name: "__kk_math_cos",
            parameters: [
                RuntimeABIParameter(name: "value", type: .intptr),
            ],
            returnType: .intptr,
            section: "Math",
            isThrowing: false
        ),
        RuntimeABIFunctionSpec(
            name: "__kk_math_tan",
            parameters: [
                RuntimeABIParameter(name: "value", type: .intptr),
            ],
            returnType: .intptr,
            section: "Math",
            isThrowing: false
        ),
        RuntimeABIFunctionSpec(
            name: "__kk_math_asin",
            parameters: [
                RuntimeABIParameter(name: "value", type: .intptr),
            ],
            returnType: .intptr,
            section: "Math",
            isThrowing: false
        ),
        RuntimeABIFunctionSpec(
            name: "__kk_math_acos",
            parameters: [
                RuntimeABIParameter(name: "value", type: .intptr),
            ],
            returnType: .intptr,
            section: "Math",
            isThrowing: false
        ),
        RuntimeABIFunctionSpec(
            name: "__kk_math_atan",
            parameters: [
                RuntimeABIParameter(name: "value", type: .intptr),
            ],
            returnType: .intptr,
            section: "Math",
            isThrowing: false
        ),
        RuntimeABIFunctionSpec(
            name: "__kk_math_atan2",
            parameters: [
                RuntimeABIParameter(name: "y", type: .intptr),
                RuntimeABIParameter(name: "x", type: .intptr),
            ],
            returnType: .intptr,
            section: "Math",
            isThrowing: false
        ),
        // STDLIB-431: exp/ln/log functions
        RuntimeABIFunctionSpec(
            name: "__kk_math_exp",
            parameters: [
                RuntimeABIParameter(name: "value", type: .intptr),
            ],
            returnType: .intptr,
            section: "Math",
            isThrowing: false
        ),
        RuntimeABIFunctionSpec(
            name: "__kk_math_expm1",
            parameters: [
                RuntimeABIParameter(name: "value", type: .intptr),
            ],
            returnType: .intptr,
            section: "Math",
            isThrowing: false
        ),
        RuntimeABIFunctionSpec(
            name: "__kk_math_ln",
            parameters: [
                RuntimeABIParameter(name: "value", type: .intptr),
            ],
            returnType: .intptr,
            section: "Math",
            isThrowing: false
        ),
        RuntimeABIFunctionSpec(
            name: "__kk_math_ln1p",
            parameters: [
                RuntimeABIParameter(name: "value", type: .intptr),
            ],
            returnType: .intptr,
            section: "Math",
            isThrowing: false
        ),
        RuntimeABIFunctionSpec(
            name: "__kk_math_log2",
            parameters: [
                RuntimeABIParameter(name: "value", type: .intptr),
            ],
            returnType: .intptr,
            section: "Math",
            isThrowing: false
        ),
        RuntimeABIFunctionSpec(
            name: "__kk_math_log10",
            parameters: [
                RuntimeABIParameter(name: "value", type: .intptr),
            ],
            returnType: .intptr,
            section: "Math",
            isThrowing: false
        ),
        RuntimeABIFunctionSpec(
            name: "__kk_math_log",
            parameters: [
                RuntimeABIParameter(name: "x", type: .intptr),
                RuntimeABIParameter(name: "base", type: .intptr),
            ],
            returnType: .intptr,
            section: "Math",
            isThrowing: false
        ),
        // STDLIB-432: hypot
        RuntimeABIFunctionSpec(
            name: "__kk_math_hypot",
            parameters: [
                RuntimeABIParameter(name: "x", type: .intptr),
                RuntimeABIParameter(name: "y", type: .intptr),
            ],
            returnType: .intptr,
            section: "Math",
            isThrowing: false
        ),
        // STDLIB-500~509: Float overloads
        RuntimeABIFunctionSpec(
            name: "__kk_math_sin_float",
            parameters: [
                RuntimeABIParameter(name: "value", type: .intptr),
            ],
            returnType: .intptr,
            section: "Math",
            isThrowing: false
        ),
        RuntimeABIFunctionSpec(
            name: "__kk_math_cos_float",
            parameters: [
                RuntimeABIParameter(name: "value", type: .intptr),
            ],
            returnType: .intptr,
            section: "Math",
            isThrowing: false
        ),
        RuntimeABIFunctionSpec(
            name: "__kk_math_tan_float",
            parameters: [
                RuntimeABIParameter(name: "value", type: .intptr),
            ],
            returnType: .intptr,
            section: "Math",
            isThrowing: false
        ),
        RuntimeABIFunctionSpec(
            name: "__kk_math_asin_float",
            parameters: [
                RuntimeABIParameter(name: "value", type: .intptr),
            ],
            returnType: .intptr,
            section: "Math",
            isThrowing: false
        ),
        RuntimeABIFunctionSpec(
            name: "__kk_math_acos_float",
            parameters: [
                RuntimeABIParameter(name: "value", type: .intptr),
            ],
            returnType: .intptr,
            section: "Math",
            isThrowing: false
        ),
        RuntimeABIFunctionSpec(
            name: "__kk_math_atan_float",
            parameters: [
                RuntimeABIParameter(name: "value", type: .intptr),
            ],
            returnType: .intptr,
            section: "Math",
            isThrowing: false
        ),
        RuntimeABIFunctionSpec(
            name: "__kk_math_atan2_float",
            parameters: [
                RuntimeABIParameter(name: "y", type: .intptr),
                RuntimeABIParameter(name: "x", type: .intptr),
            ],
            returnType: .intptr,
            section: "Math",
            isThrowing: false
        ),
        RuntimeABIFunctionSpec(
            name: "__kk_math_sqrt_float",
            parameters: [
                RuntimeABIParameter(name: "value", type: .intptr),
            ],
            returnType: .intptr,
            section: "Math",
            isThrowing: false
        ),
        RuntimeABIFunctionSpec(
            name: "__kk_math_round_float",
            parameters: [
                RuntimeABIParameter(name: "value", type: .intptr),
            ],
            returnType: .intptr,
            section: "Math",
            isThrowing: false
        ),
        RuntimeABIFunctionSpec(
            name: "__kk_math_ceil_float",
            parameters: [
                RuntimeABIParameter(name: "value", type: .intptr),
            ],
            returnType: .intptr,
            section: "Math",
            isThrowing: false
        ),
        RuntimeABIFunctionSpec(
            name: "__kk_math_floor_float",
            parameters: [
                RuntimeABIParameter(name: "value", type: .intptr),
            ],
            returnType: .intptr,
            section: "Math",
            isThrowing: false
        ),
        // STDLIB-430: additional Float overloads (exp, expm1, ln, ln1p, log2, log10, log, hypot)
        RuntimeABIFunctionSpec(
            name: "__kk_math_exp_float",
            parameters: [RuntimeABIParameter(name: "value", type: .intptr)],
            returnType: .intptr,
            section: "Math",
            isThrowing: false
        ),
        RuntimeABIFunctionSpec(
            name: "__kk_math_expm1_float",
            parameters: [RuntimeABIParameter(name: "value", type: .intptr)],
            returnType: .intptr,
            section: "Math",
            isThrowing: false
        ),
        RuntimeABIFunctionSpec(
            name: "__kk_math_ln_float",
            parameters: [RuntimeABIParameter(name: "value", type: .intptr)],
            returnType: .intptr,
            section: "Math",
            isThrowing: false
        ),
        RuntimeABIFunctionSpec(
            name: "__kk_math_ln1p_float",
            parameters: [RuntimeABIParameter(name: "value", type: .intptr)],
            returnType: .intptr,
            section: "Math",
            isThrowing: false
        ),
        RuntimeABIFunctionSpec(
            name: "__kk_math_log2_float",
            parameters: [RuntimeABIParameter(name: "value", type: .intptr)],
            returnType: .intptr,
            section: "Math",
            isThrowing: false
        ),
        RuntimeABIFunctionSpec(
            name: "__kk_math_log10_float",
            parameters: [RuntimeABIParameter(name: "value", type: .intptr)],
            returnType: .intptr,
            section: "Math",
            isThrowing: false
        ),
        RuntimeABIFunctionSpec(
            name: "__kk_math_log_float",
            parameters: [
                RuntimeABIParameter(name: "x", type: .intptr),
                RuntimeABIParameter(name: "base", type: .intptr),
            ],
            returnType: .intptr,
            section: "Math",
            isThrowing: false
        ),
        RuntimeABIFunctionSpec(
            name: "__kk_math_hypot_float",
            parameters: [
                RuntimeABIParameter(name: "x", type: .intptr),
                RuntimeABIParameter(name: "y", type: .intptr),
            ],
            returnType: .intptr,
            section: "Math",
            isThrowing: false
        ),
        // STDLIB-510~511: roundToInt / roundToLong
        // Throwing callees: NaN receiver throws IllegalArgumentException, so the
        // ABI carries the trailing outThrown pointer (see RuntimeNumericCompat).
        RuntimeABIFunctionSpec(
            name: "__kk_float_roundToInt",
            parameters: [
                RuntimeABIParameter(name: "value", type: .intptr),
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "Math"
        ),
        RuntimeABIFunctionSpec(
            name: "__kk_double_roundToInt",
            parameters: [
                RuntimeABIParameter(name: "value", type: .intptr),
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "Math"
        ),
        RuntimeABIFunctionSpec(
            name: "__kk_float_roundToLong",
            parameters: [
                RuntimeABIParameter(name: "value", type: .intptr),
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "Math"
        ),
        RuntimeABIFunctionSpec(
            name: "__kk_double_roundToLong",
            parameters: [
                RuntimeABIParameter(name: "value", type: .intptr),
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "Math"
        ),
        // STDLIB-512~513: ulp / nextUp / nextDown
        RuntimeABIFunctionSpec(
            name: "__kk_double_ulp",
            parameters: [
                RuntimeABIParameter(name: "value", type: .intptr),
            ],
            returnType: .intptr,
            section: "Math",
            isThrowing: false
        ),
        RuntimeABIFunctionSpec(
            name: "__kk_double_nextUp",
            parameters: [
                RuntimeABIParameter(name: "value", type: .intptr),
            ],
            returnType: .intptr,
            section: "Math",
            isThrowing: false
        ),
        RuntimeABIFunctionSpec(
            name: "__kk_double_nextDown",
            parameters: [
                RuntimeABIParameter(name: "value", type: .intptr),
            ],
            returnType: .intptr,
            section: "Math",
            isThrowing: false
        ),
        RuntimeABIFunctionSpec(
            name: "__kk_float_ulp",
            parameters: [
                RuntimeABIParameter(name: "value", type: .intptr),
            ],
            returnType: .intptr,
            section: "Math",
            isThrowing: false
        ),
        RuntimeABIFunctionSpec(
            name: "__kk_float_nextUp",
            parameters: [
                RuntimeABIParameter(name: "value", type: .intptr),
            ],
            returnType: .intptr,
            section: "Math",
            isThrowing: false
        ),
        RuntimeABIFunctionSpec(
            name: "__kk_float_nextDown",
            parameters: [
                RuntimeABIParameter(name: "value", type: .intptr),
            ],
            returnType: .intptr,
            section: "Math",
            isThrowing: false
        ),
        // STDLIB-514: truncate
        RuntimeABIFunctionSpec(
            name: "__kk_math_truncate",
            parameters: [
                RuntimeABIParameter(name: "value", type: .intptr),
            ],
            returnType: .intptr,
            section: "Math"
        ),
        RuntimeABIFunctionSpec(
            name: "__kk_math_truncate_float",
            parameters: [
                RuntimeABIParameter(name: "value", type: .intptr),
            ],
            returnType: .intptr,
            section: "Math"
        ),
        // STDLIB-MATH-113: Inverse hyperbolic functions
        RuntimeABIFunctionSpec(
            name: "__kk_math_acosh",
            parameters: [
                RuntimeABIParameter(name: "value", type: .intptr),
            ],
            returnType: .intptr,
            section: "Math"
        ),
        RuntimeABIFunctionSpec(
            name: "__kk_math_asinh",
            parameters: [
                RuntimeABIParameter(name: "value", type: .intptr),
            ],
            returnType: .intptr,
            section: "Math"
        ),
        RuntimeABIFunctionSpec(
            name: "__kk_math_atanh",
            parameters: [
                RuntimeABIParameter(name: "value", type: .intptr),
            ],
            returnType: .intptr,
            section: "Math"
        ),
        RuntimeABIFunctionSpec(
            name: "__kk_math_acosh_float",
            parameters: [
                RuntimeABIParameter(name: "value", type: .intptr),
            ],
            returnType: .intptr,
            section: "Math"
        ),
        RuntimeABIFunctionSpec(
            name: "__kk_math_asinh_float",
            parameters: [
                RuntimeABIParameter(name: "value", type: .intptr),
            ],
            returnType: .intptr,
            section: "Math"
        ),
        RuntimeABIFunctionSpec(
            name: "__kk_math_atanh_float",
            parameters: [
                RuntimeABIParameter(name: "value", type: .intptr),
            ],
            returnType: .intptr,
            section: "Math"
        ),
        // STDLIB-MATH-109: Hyperbolic functions and cbrt
        RuntimeABIFunctionSpec(
            name: "__kk_math_sinh",
            parameters: [
                RuntimeABIParameter(name: "value", type: .intptr),
            ],
            returnType: .intptr,
            section: "Math",
            isThrowing: false
        ),
        RuntimeABIFunctionSpec(
            name: "__kk_math_cosh",
            parameters: [
                RuntimeABIParameter(name: "value", type: .intptr),
            ],
            returnType: .intptr,
            section: "Math",
            isThrowing: false
        ),
        RuntimeABIFunctionSpec(
            name: "__kk_math_tanh",
            parameters: [
                RuntimeABIParameter(name: "value", type: .intptr),
            ],
            returnType: .intptr,
            section: "Math",
            isThrowing: false
        ),
        RuntimeABIFunctionSpec(
            name: "__kk_math_cbrt",
            parameters: [
                RuntimeABIParameter(name: "value", type: .intptr),
            ],
            returnType: .intptr,
            section: "Math",
            isThrowing: false
        ),
        RuntimeABIFunctionSpec(
            name: "__kk_math_sinh_float",
            parameters: [
                RuntimeABIParameter(name: "value", type: .intptr),
            ],
            returnType: .intptr,
            section: "Math",
            isThrowing: false
        ),
        RuntimeABIFunctionSpec(
            name: "__kk_math_cosh_float",
            parameters: [
                RuntimeABIParameter(name: "value", type: .intptr),
            ],
            returnType: .intptr,
            section: "Math",
            isThrowing: false
        ),
        RuntimeABIFunctionSpec(
            name: "__kk_math_tanh_float",
            parameters: [
                RuntimeABIParameter(name: "value", type: .intptr),
            ],
            returnType: .intptr,
            section: "Math",
            isThrowing: false
        ),
        RuntimeABIFunctionSpec(
            name: "__kk_math_cbrt_float",
            parameters: [
                RuntimeABIParameter(name: "value", type: .intptr),
            ],
            returnType: .intptr,
            section: "Math",
            isThrowing: false
        ),
        // STDLIB-MATH-112: numeric constants — Double special values
        RuntimeABIFunctionSpec(name: "kk_double_positive_infinity", parameters: [], returnType: .intptr, section: "Math"),
        RuntimeABIFunctionSpec(name: "kk_double_negative_infinity", parameters: [], returnType: .intptr, section: "Math"),
        RuntimeABIFunctionSpec(name: "kk_double_nan", parameters: [], returnType: .intptr, section: "Math"),
        RuntimeABIFunctionSpec(name: "kk_double_max_value", parameters: [], returnType: .intptr, section: "Math"),
        RuntimeABIFunctionSpec(name: "kk_double_min_value", parameters: [], returnType: .intptr, section: "Math"),
    ]
}
