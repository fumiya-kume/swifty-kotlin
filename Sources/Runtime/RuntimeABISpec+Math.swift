// Math functions (STDLIB-052).

public extension RuntimeABISpec {
    static let mathFunctions: [RuntimeABIFunctionSpec] = [
        RuntimeABIFunctionSpec(
            name: "kk_math_abs_int",
            parameters: [
                RuntimeABIParameter(name: "value", type: .intptr),
            ],
            returnType: .intptr,
            section: "Math"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_math_abs",
            parameters: [
                RuntimeABIParameter(name: "value", type: .intptr),
            ],
            returnType: .intptr,
            section: "Math"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_math_sqrt",
            parameters: [
                RuntimeABIParameter(name: "value", type: .intptr),
            ],
            returnType: .intptr,
            section: "Math"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_math_pow",
            parameters: [
                RuntimeABIParameter(name: "base", type: .intptr),
                RuntimeABIParameter(name: "exp", type: .intptr),
            ],
            returnType: .intptr,
            section: "Math"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_math_ceil",
            parameters: [
                RuntimeABIParameter(name: "value", type: .intptr),
            ],
            returnType: .intptr,
            section: "Math"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_math_floor",
            parameters: [
                RuntimeABIParameter(name: "value", type: .intptr),
            ],
            returnType: .intptr,
            section: "Math"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_math_round",
            parameters: [
                RuntimeABIParameter(name: "value", type: .intptr),
            ],
            returnType: .intptr,
            section: "Math"
        ),
        // Trigonometric functions (STDLIB-430)
        // Note: Each trig entry is spelled out individually rather than generated
        // programmatically. This repetition is intentional — the ABI spec must be
        // a plain, auditable list so that any ABI-breaking change is visible in
        // code review as a concrete diff, not hidden behind abstraction.
        RuntimeABIFunctionSpec(
            name: "kk_math_sin",
            parameters: [
                RuntimeABIParameter(name: "value", type: .intptr),
            ],
            returnType: .intptr,
            section: "Math"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_math_cos",
            parameters: [
                RuntimeABIParameter(name: "value", type: .intptr),
            ],
            returnType: .intptr,
            section: "Math"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_math_tan",
            parameters: [
                RuntimeABIParameter(name: "value", type: .intptr),
            ],
            returnType: .intptr,
            section: "Math"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_math_asin",
            parameters: [
                RuntimeABIParameter(name: "value", type: .intptr),
            ],
            returnType: .intptr,
            section: "Math"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_math_acos",
            parameters: [
                RuntimeABIParameter(name: "value", type: .intptr),
            ],
            returnType: .intptr,
            section: "Math"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_math_atan",
            parameters: [
                RuntimeABIParameter(name: "value", type: .intptr),
            ],
            returnType: .intptr,
            section: "Math"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_math_atan2",
            parameters: [
                RuntimeABIParameter(name: "y", type: .intptr),
                RuntimeABIParameter(name: "x", type: .intptr),
            ],
            returnType: .intptr,
            section: "Math"
        ),
        // STDLIB-431: exp/ln/log functions
        RuntimeABIFunctionSpec(
            name: "kk_math_exp",
            parameters: [
                RuntimeABIParameter(name: "value", type: .intptr),
            ],
            returnType: .intptr,
            section: "Math"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_math_ln",
            parameters: [
                RuntimeABIParameter(name: "value", type: .intptr),
            ],
            returnType: .intptr,
            section: "Math"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_math_log2",
            parameters: [
                RuntimeABIParameter(name: "value", type: .intptr),
            ],
            returnType: .intptr,
            section: "Math"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_math_log10",
            parameters: [
                RuntimeABIParameter(name: "value", type: .intptr),
            ],
            returnType: .intptr,
            section: "Math"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_math_log",
            parameters: [
                RuntimeABIParameter(name: "x", type: .intptr),
                RuntimeABIParameter(name: "base", type: .intptr),
            ],
            returnType: .intptr,
            section: "Math"
        ),
        // STDLIB-432: sign/hypot + PI/E constants
        RuntimeABIFunctionSpec(
            name: "kk_math_sign",
            parameters: [
                RuntimeABIParameter(name: "value", type: .intptr),
            ],
            returnType: .intptr,
            section: "Math"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_math_hypot",
            parameters: [
                RuntimeABIParameter(name: "x", type: .intptr),
                RuntimeABIParameter(name: "y", type: .intptr),
            ],
            returnType: .intptr,
            section: "Math"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_math_PI",
            parameters: [],
            returnType: .intptr,
            section: "Math"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_math_E",
            parameters: [],
            returnType: .intptr,
            section: "Math"
        ),
        // STDLIB-500~509: Float overloads
        RuntimeABIFunctionSpec(
            name: "kk_math_sin_float",
            parameters: [
                RuntimeABIParameter(name: "value", type: .intptr),
            ],
            returnType: .intptr,
            section: "Math"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_math_cos_float",
            parameters: [
                RuntimeABIParameter(name: "value", type: .intptr),
            ],
            returnType: .intptr,
            section: "Math"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_math_tan_float",
            parameters: [
                RuntimeABIParameter(name: "value", type: .intptr),
            ],
            returnType: .intptr,
            section: "Math"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_math_asin_float",
            parameters: [
                RuntimeABIParameter(name: "value", type: .intptr),
            ],
            returnType: .intptr,
            section: "Math"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_math_acos_float",
            parameters: [
                RuntimeABIParameter(name: "value", type: .intptr),
            ],
            returnType: .intptr,
            section: "Math"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_math_atan_float",
            parameters: [
                RuntimeABIParameter(name: "value", type: .intptr),
            ],
            returnType: .intptr,
            section: "Math"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_math_atan2_float",
            parameters: [
                RuntimeABIParameter(name: "y", type: .intptr),
                RuntimeABIParameter(name: "x", type: .intptr),
            ],
            returnType: .intptr,
            section: "Math"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_math_sqrt_float",
            parameters: [
                RuntimeABIParameter(name: "value", type: .intptr),
            ],
            returnType: .intptr,
            section: "Math"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_math_round_float",
            parameters: [
                RuntimeABIParameter(name: "value", type: .intptr),
            ],
            returnType: .intptr,
            section: "Math"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_math_ceil_float",
            parameters: [
                RuntimeABIParameter(name: "value", type: .intptr),
            ],
            returnType: .intptr,
            section: "Math"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_math_floor_float",
            parameters: [
                RuntimeABIParameter(name: "value", type: .intptr),
            ],
            returnType: .intptr,
            section: "Math"
        ),
        // STDLIB-430: additional Float overloads (abs, exp, ln, log2, log10, log, sign, hypot)
        RuntimeABIFunctionSpec(
            name: "kk_math_abs_float",
            parameters: [RuntimeABIParameter(name: "value", type: .intptr)],
            returnType: .intptr,
            section: "Math"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_math_exp_float",
            parameters: [RuntimeABIParameter(name: "value", type: .intptr)],
            returnType: .intptr,
            section: "Math"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_math_ln_float",
            parameters: [RuntimeABIParameter(name: "value", type: .intptr)],
            returnType: .intptr,
            section: "Math"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_math_log2_float",
            parameters: [RuntimeABIParameter(name: "value", type: .intptr)],
            returnType: .intptr,
            section: "Math"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_math_log10_float",
            parameters: [RuntimeABIParameter(name: "value", type: .intptr)],
            returnType: .intptr,
            section: "Math"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_math_log_float",
            parameters: [
                RuntimeABIParameter(name: "x", type: .intptr),
                RuntimeABIParameter(name: "base", type: .intptr),
            ],
            returnType: .intptr,
            section: "Math"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_math_sign_float",
            parameters: [RuntimeABIParameter(name: "value", type: .intptr)],
            returnType: .intptr,
            section: "Math"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_math_hypot_float",
            parameters: [
                RuntimeABIParameter(name: "x", type: .intptr),
                RuntimeABIParameter(name: "y", type: .intptr),
            ],
            returnType: .intptr,
            section: "Math"
        ),
        // STDLIB-510~511: roundToInt / roundToLong
        RuntimeABIFunctionSpec(
            name: "kk_float_roundToInt",
            parameters: [
                RuntimeABIParameter(name: "value", type: .intptr),
            ],
            returnType: .intptr,
            section: "Math"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_double_roundToInt",
            parameters: [
                RuntimeABIParameter(name: "value", type: .intptr),
            ],
            returnType: .intptr,
            section: "Math"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_float_roundToLong",
            parameters: [
                RuntimeABIParameter(name: "value", type: .intptr),
            ],
            returnType: .intptr,
            section: "Math"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_double_roundToLong",
            parameters: [
                RuntimeABIParameter(name: "value", type: .intptr),
            ],
            returnType: .intptr,
            section: "Math"
        ),
        // STDLIB-512~513: ulp / nextUp / nextDown
        RuntimeABIFunctionSpec(
            name: "kk_double_ulp",
            parameters: [
                RuntimeABIParameter(name: "value", type: .intptr),
            ],
            returnType: .intptr,
            section: "Math"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_double_nextUp",
            parameters: [
                RuntimeABIParameter(name: "value", type: .intptr),
            ],
            returnType: .intptr,
            section: "Math"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_double_nextDown",
            parameters: [
                RuntimeABIParameter(name: "value", type: .intptr),
            ],
            returnType: .intptr,
            section: "Math"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_float_ulp",
            parameters: [
                RuntimeABIParameter(name: "value", type: .intptr),
            ],
            returnType: .intptr,
            section: "Math"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_float_nextUp",
            parameters: [
                RuntimeABIParameter(name: "value", type: .intptr),
            ],
            returnType: .intptr,
            section: "Math"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_float_nextDown",
            parameters: [
                RuntimeABIParameter(name: "value", type: .intptr),
            ],
            returnType: .intptr,
            section: "Math"
        ),
        // STDLIB-514: abs(Long), truncate
        RuntimeABIFunctionSpec(
            name: "kk_math_abs_long",
            parameters: [
                RuntimeABIParameter(name: "value", type: .intptr),
            ],
            returnType: .intptr,
            section: "Math"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_math_truncate",
            parameters: [
                RuntimeABIParameter(name: "value", type: .intptr),
            ],
            returnType: .intptr,
            section: "Math"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_math_truncate_float",
            parameters: [
                RuntimeABIParameter(name: "value", type: .intptr),
            ],
            returnType: .intptr,
            section: "Math"
        ),
    ]
}
