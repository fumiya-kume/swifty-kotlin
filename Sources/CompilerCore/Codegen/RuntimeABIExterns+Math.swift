// MARK: - Math (STDLIB-052)

public extension RuntimeABIExterns {
    static let mathExterns: [ExternDecl] = [
        kk_math_abs_int,
        kk_math_abs,
        kk_math_sqrt,
        kk_math_pow,
        kk_math_ceil,
        kk_math_floor,
        kk_math_round,
        kk_math_sin,
        kk_math_cos,
        kk_math_tan,
        kk_math_asin,
        kk_math_acos,
        kk_math_atan,
        kk_math_atan2,
        // STDLIB-431: exp/ln/log functions
        kk_math_exp,
        kk_math_ln,
        kk_math_log2,
        kk_math_log10,
        kk_math_log,
        // STDLIB-432: sign/hypot + PI/E constants
        kk_math_sign,
        kk_math_hypot,
        kk_math_PI,
        kk_math_E,
        // STDLIB-500~509: Float overloads
        kk_math_sin_float,
        kk_math_cos_float,
        kk_math_tan_float,
        kk_math_asin_float,
        kk_math_acos_float,
        kk_math_atan_float,
        kk_math_atan2_float,
        kk_math_sqrt_float,
        kk_math_round_float,
        kk_math_ceil_float,
        kk_math_floor_float,
        kk_math_abs_float,
        kk_math_exp_float,
        kk_math_ln_float,
        kk_math_log2_float,
        kk_math_log10_float,
        kk_math_log_float,
        kk_math_sign_float,
        kk_math_hypot_float,
        // STDLIB-510~511: roundToInt / roundToLong
        kk_float_roundToInt,
        kk_double_roundToInt,
        kk_float_roundToLong,
        kk_double_roundToLong,
        // STDLIB-512~513: ulp / nextUp / nextDown
        kk_double_ulp,
        kk_double_nextUp,
        kk_double_nextDown,
        kk_float_ulp,
        kk_float_nextUp,
        kk_float_nextDown,
        // STDLIB-514: abs(Long), truncate
        kk_math_abs_long,
        kk_math_truncate,
        kk_math_truncate_float,
        // STDLIB-111: IEEE 754 rounding modes
        kk_math_round_mode,
        kk_math_round_mode_float,
        kk_math_round_up,
        kk_math_round_down,
        kk_math_round_ceiling,
        kk_math_round_floor,
        kk_math_round_half_up,
        kk_math_round_half_down,
        kk_math_round_half_even,
        kk_math_round_unnecessary,
        kk_math_round_up_float,
        kk_math_round_down_float,
        kk_math_round_ceiling_float,
        kk_math_round_floor_float,
        kk_math_round_half_up_float,
        kk_math_round_half_down_float,
        kk_math_round_half_even_float,
        kk_math_round_unnecessary_float,
        // STDLIB-MATH-109: Hyperbolic functions and cbrt
        kk_math_sinh,
        kk_math_cosh,
        kk_math_tanh,
        kk_math_cbrt,
        kk_math_sinh_float,
        kk_math_cosh_float,
        kk_math_tanh_float,
        kk_math_cbrt_float,
        // STDLIB-MATH-112: numeric constants
        kk_double_positive_infinity,
        kk_double_negative_infinity,
        kk_double_nan,
        kk_double_max_value,
        kk_double_min_value,
        kk_float_positive_infinity,
        kk_float_negative_infinity,
        kk_float_nan,
        kk_float_max_value,
        kk_float_min_value,
        kk_int_max_value,
        kk_int_min_value,
        kk_long_max_value,
        kk_long_min_value,
    ]

    static let kk_math_abs_int = ExternDecl(
        name: "kk_math_abs_int",
        parameterTypes: ["intptr_t"],
        returnType: "intptr_t"
    )

    static let kk_math_abs = ExternDecl(
        name: "kk_math_abs",
        parameterTypes: ["intptr_t"],
        returnType: "intptr_t"
    )

    static let kk_math_sqrt = ExternDecl(
        name: "kk_math_sqrt",
        parameterTypes: ["intptr_t"],
        returnType: "intptr_t"
    )

    static let kk_math_pow = ExternDecl(
        name: "kk_math_pow",
        parameterTypes: ["intptr_t", "intptr_t"],
        returnType: "intptr_t"
    )

    static let kk_math_ceil = ExternDecl(
        name: "kk_math_ceil",
        parameterTypes: ["intptr_t"],
        returnType: "intptr_t"
    )

    static let kk_math_floor = ExternDecl(
        name: "kk_math_floor",
        parameterTypes: ["intptr_t"],
        returnType: "intptr_t"
    )

    static let kk_math_round = ExternDecl(
        name: "kk_math_round",
        parameterTypes: ["intptr_t"],
        returnType: "intptr_t"
    )

    // Trigonometric functions (STDLIB-430)

    static let kk_math_sin = ExternDecl(
        name: "kk_math_sin",
        parameterTypes: ["intptr_t"],
        returnType: "intptr_t"
    )

    static let kk_math_cos = ExternDecl(
        name: "kk_math_cos",
        parameterTypes: ["intptr_t"],
        returnType: "intptr_t"
    )

    static let kk_math_tan = ExternDecl(
        name: "kk_math_tan",
        parameterTypes: ["intptr_t"],
        returnType: "intptr_t"
    )

    static let kk_math_asin = ExternDecl(
        name: "kk_math_asin",
        parameterTypes: ["intptr_t"],
        returnType: "intptr_t"
    )

    static let kk_math_acos = ExternDecl(
        name: "kk_math_acos",
        parameterTypes: ["intptr_t"],
        returnType: "intptr_t"
    )

    static let kk_math_atan = ExternDecl(
        name: "kk_math_atan",
        parameterTypes: ["intptr_t"],
        returnType: "intptr_t"
    )

    static let kk_math_atan2 = ExternDecl(
        name: "kk_math_atan2",
        parameterTypes: ["intptr_t", "intptr_t"],
        returnType: "intptr_t"
    )

    // STDLIB-431: exp/ln/log functions

    static let kk_math_exp = ExternDecl(
        name: "kk_math_exp",
        parameterTypes: ["intptr_t"],
        returnType: "intptr_t"
    )

    static let kk_math_ln = ExternDecl(
        name: "kk_math_ln",
        parameterTypes: ["intptr_t"],
        returnType: "intptr_t"
    )

    static let kk_math_log2 = ExternDecl(
        name: "kk_math_log2",
        parameterTypes: ["intptr_t"],
        returnType: "intptr_t"
    )

    static let kk_math_log10 = ExternDecl(
        name: "kk_math_log10",
        parameterTypes: ["intptr_t"],
        returnType: "intptr_t"
    )

    static let kk_math_log = ExternDecl(
        name: "kk_math_log",
        parameterTypes: ["intptr_t", "intptr_t"],
        returnType: "intptr_t"
    )

    // STDLIB-432: sign/hypot + PI/E constants

    static let kk_math_sign = ExternDecl(
        name: "kk_math_sign",
        parameterTypes: ["intptr_t"],
        returnType: "intptr_t"
    )

    static let kk_math_hypot = ExternDecl(
        name: "kk_math_hypot",
        parameterTypes: ["intptr_t", "intptr_t"],
        returnType: "intptr_t"
    )

    static let kk_math_PI = ExternDecl(
        name: "kk_math_PI",
        parameterTypes: [],
        returnType: "intptr_t"
    )

    static let kk_math_E = ExternDecl(
        name: "kk_math_E",
        parameterTypes: [],
        returnType: "intptr_t"
    )

    // STDLIB-500~509: Float overloads

    static let kk_math_sin_float = ExternDecl(name: "kk_math_sin_float", parameterTypes: ["intptr_t"], returnType: "intptr_t")
    static let kk_math_cos_float = ExternDecl(name: "kk_math_cos_float", parameterTypes: ["intptr_t"], returnType: "intptr_t")
    static let kk_math_tan_float = ExternDecl(name: "kk_math_tan_float", parameterTypes: ["intptr_t"], returnType: "intptr_t")
    static let kk_math_asin_float = ExternDecl(name: "kk_math_asin_float", parameterTypes: ["intptr_t"], returnType: "intptr_t")
    static let kk_math_acos_float = ExternDecl(name: "kk_math_acos_float", parameterTypes: ["intptr_t"], returnType: "intptr_t")
    static let kk_math_atan_float = ExternDecl(name: "kk_math_atan_float", parameterTypes: ["intptr_t"], returnType: "intptr_t")
    static let kk_math_atan2_float = ExternDecl(name: "kk_math_atan2_float", parameterTypes: ["intptr_t", "intptr_t"], returnType: "intptr_t")
    static let kk_math_sqrt_float = ExternDecl(name: "kk_math_sqrt_float", parameterTypes: ["intptr_t"], returnType: "intptr_t")
    static let kk_math_round_float = ExternDecl(name: "kk_math_round_float", parameterTypes: ["intptr_t"], returnType: "intptr_t")
    static let kk_math_ceil_float = ExternDecl(name: "kk_math_ceil_float", parameterTypes: ["intptr_t"], returnType: "intptr_t")
    static let kk_math_floor_float = ExternDecl(name: "kk_math_floor_float", parameterTypes: ["intptr_t"], returnType: "intptr_t")
    static let kk_math_abs_float = ExternDecl(name: "kk_math_abs_float", parameterTypes: ["intptr_t"], returnType: "intptr_t")
    static let kk_math_exp_float = ExternDecl(name: "kk_math_exp_float", parameterTypes: ["intptr_t"], returnType: "intptr_t")
    static let kk_math_ln_float = ExternDecl(name: "kk_math_ln_float", parameterTypes: ["intptr_t"], returnType: "intptr_t")
    static let kk_math_log2_float = ExternDecl(name: "kk_math_log2_float", parameterTypes: ["intptr_t"], returnType: "intptr_t")
    static let kk_math_log10_float = ExternDecl(name: "kk_math_log10_float", parameterTypes: ["intptr_t"], returnType: "intptr_t")
    static let kk_math_log_float = ExternDecl(name: "kk_math_log_float", parameterTypes: ["intptr_t", "intptr_t"], returnType: "intptr_t")
    static let kk_math_sign_float = ExternDecl(name: "kk_math_sign_float", parameterTypes: ["intptr_t"], returnType: "intptr_t")
    static let kk_math_hypot_float = ExternDecl(name: "kk_math_hypot_float", parameterTypes: ["intptr_t", "intptr_t"], returnType: "intptr_t")

    // STDLIB-510~511: roundToInt / roundToLong

    static let kk_float_roundToInt = ExternDecl(name: "kk_float_roundToInt", parameterTypes: ["intptr_t"], returnType: "intptr_t")
    static let kk_double_roundToInt = ExternDecl(name: "kk_double_roundToInt", parameterTypes: ["intptr_t"], returnType: "intptr_t")
    static let kk_float_roundToLong = ExternDecl(name: "kk_float_roundToLong", parameterTypes: ["intptr_t"], returnType: "intptr_t")
    static let kk_double_roundToLong = ExternDecl(name: "kk_double_roundToLong", parameterTypes: ["intptr_t"], returnType: "intptr_t")

    // STDLIB-512~513: ulp / nextUp / nextDown

    static let kk_double_ulp = ExternDecl(name: "kk_double_ulp", parameterTypes: ["intptr_t"], returnType: "intptr_t")
    static let kk_double_nextUp = ExternDecl(name: "kk_double_nextUp", parameterTypes: ["intptr_t"], returnType: "intptr_t")
    static let kk_double_nextDown = ExternDecl(name: "kk_double_nextDown", parameterTypes: ["intptr_t"], returnType: "intptr_t")
    static let kk_float_ulp = ExternDecl(name: "kk_float_ulp", parameterTypes: ["intptr_t"], returnType: "intptr_t")
    static let kk_float_nextUp = ExternDecl(name: "kk_float_nextUp", parameterTypes: ["intptr_t"], returnType: "intptr_t")
    static let kk_float_nextDown = ExternDecl(name: "kk_float_nextDown", parameterTypes: ["intptr_t"], returnType: "intptr_t")

    // STDLIB-514: abs(Long), truncate

    static let kk_math_abs_long = ExternDecl(name: "kk_math_abs_long", parameterTypes: ["intptr_t"], returnType: "intptr_t")
    static let kk_math_truncate = ExternDecl(name: "kk_math_truncate", parameterTypes: ["intptr_t"], returnType: "intptr_t")
    static let kk_math_truncate_float = ExternDecl(name: "kk_math_truncate_float", parameterTypes: ["intptr_t"], returnType: "intptr_t")

    // STDLIB-111: IEEE 754 rounding modes — generic mode-dispatch
    static let kk_math_round_mode = ExternDecl(name: "kk_math_round_mode", parameterTypes: ["intptr_t", "intptr_t"], returnType: "intptr_t")
    static let kk_math_round_mode_float = ExternDecl(name: "kk_math_round_mode_float", parameterTypes: ["intptr_t", "intptr_t"], returnType: "intptr_t")

    // STDLIB-111: IEEE 754 rounding modes — Double convenience entry points
    static let kk_math_round_up = ExternDecl(name: "kk_math_round_up", parameterTypes: ["intptr_t"], returnType: "intptr_t")
    static let kk_math_round_down = ExternDecl(name: "kk_math_round_down", parameterTypes: ["intptr_t"], returnType: "intptr_t")
    static let kk_math_round_ceiling = ExternDecl(name: "kk_math_round_ceiling", parameterTypes: ["intptr_t"], returnType: "intptr_t")
    static let kk_math_round_floor = ExternDecl(name: "kk_math_round_floor", parameterTypes: ["intptr_t"], returnType: "intptr_t")
    static let kk_math_round_half_up = ExternDecl(name: "kk_math_round_half_up", parameterTypes: ["intptr_t"], returnType: "intptr_t")
    static let kk_math_round_half_down = ExternDecl(name: "kk_math_round_half_down", parameterTypes: ["intptr_t"], returnType: "intptr_t")
    static let kk_math_round_half_even = ExternDecl(name: "kk_math_round_half_even", parameterTypes: ["intptr_t"], returnType: "intptr_t")
    static let kk_math_round_unnecessary = ExternDecl(name: "kk_math_round_unnecessary", parameterTypes: ["intptr_t"], returnType: "intptr_t")

    // STDLIB-111: IEEE 754 rounding modes — Float convenience entry points
    static let kk_math_round_up_float = ExternDecl(name: "kk_math_round_up_float", parameterTypes: ["intptr_t"], returnType: "intptr_t")
    static let kk_math_round_down_float = ExternDecl(name: "kk_math_round_down_float", parameterTypes: ["intptr_t"], returnType: "intptr_t")
    static let kk_math_round_ceiling_float = ExternDecl(name: "kk_math_round_ceiling_float", parameterTypes: ["intptr_t"], returnType: "intptr_t")
    static let kk_math_round_floor_float = ExternDecl(name: "kk_math_round_floor_float", parameterTypes: ["intptr_t"], returnType: "intptr_t")
    static let kk_math_round_half_up_float = ExternDecl(name: "kk_math_round_half_up_float", parameterTypes: ["intptr_t"], returnType: "intptr_t")
    static let kk_math_round_half_down_float = ExternDecl(name: "kk_math_round_half_down_float", parameterTypes: ["intptr_t"], returnType: "intptr_t")
    static let kk_math_round_half_even_float = ExternDecl(name: "kk_math_round_half_even_float", parameterTypes: ["intptr_t"], returnType: "intptr_t")
    static let kk_math_round_unnecessary_float = ExternDecl(name: "kk_math_round_unnecessary_float", parameterTypes: ["intptr_t"], returnType: "intptr_t")
    // STDLIB-MATH-109: Hyperbolic functions and cbrt
    static let kk_math_sinh = ExternDecl(name: "kk_math_sinh", parameterTypes: ["intptr_t"], returnType: "intptr_t")
    static let kk_math_cosh = ExternDecl(name: "kk_math_cosh", parameterTypes: ["intptr_t"], returnType: "intptr_t")
    static let kk_math_tanh = ExternDecl(name: "kk_math_tanh", parameterTypes: ["intptr_t"], returnType: "intptr_t")
    static let kk_math_cbrt = ExternDecl(name: "kk_math_cbrt", parameterTypes: ["intptr_t"], returnType: "intptr_t")
    static let kk_math_sinh_float = ExternDecl(name: "kk_math_sinh_float", parameterTypes: ["intptr_t"], returnType: "intptr_t")
    static let kk_math_cosh_float = ExternDecl(name: "kk_math_cosh_float", parameterTypes: ["intptr_t"], returnType: "intptr_t")
    static let kk_math_tanh_float = ExternDecl(name: "kk_math_tanh_float", parameterTypes: ["intptr_t"], returnType: "intptr_t")
    static let kk_math_cbrt_float = ExternDecl(name: "kk_math_cbrt_float", parameterTypes: ["intptr_t"], returnType: "intptr_t")
    // STDLIB-MATH-112: numeric constants — Double special values
    static let kk_double_positive_infinity = ExternDecl(name: "kk_double_positive_infinity", parameterTypes: [], returnType: "intptr_t")
    static let kk_double_negative_infinity = ExternDecl(name: "kk_double_negative_infinity", parameterTypes: [], returnType: "intptr_t")
    static let kk_double_nan = ExternDecl(name: "kk_double_nan", parameterTypes: [], returnType: "intptr_t")
    static let kk_double_max_value = ExternDecl(name: "kk_double_max_value", parameterTypes: [], returnType: "intptr_t")
    static let kk_double_min_value = ExternDecl(name: "kk_double_min_value", parameterTypes: [], returnType: "intptr_t")

    // STDLIB-MATH-112: numeric constants — Float special values
    static let kk_float_positive_infinity = ExternDecl(name: "kk_float_positive_infinity", parameterTypes: [], returnType: "intptr_t")
    static let kk_float_negative_infinity = ExternDecl(name: "kk_float_negative_infinity", parameterTypes: [], returnType: "intptr_t")
    static let kk_float_nan = ExternDecl(name: "kk_float_nan", parameterTypes: [], returnType: "intptr_t")
    static let kk_float_max_value = ExternDecl(name: "kk_float_max_value", parameterTypes: [], returnType: "intptr_t")
    static let kk_float_min_value = ExternDecl(name: "kk_float_min_value", parameterTypes: [], returnType: "intptr_t")

    // STDLIB-MATH-112: numeric constants — Int/Long bounds
    static let kk_int_max_value = ExternDecl(name: "kk_int_max_value", parameterTypes: [], returnType: "intptr_t")
    static let kk_int_min_value = ExternDecl(name: "kk_int_min_value", parameterTypes: [], returnType: "intptr_t")
    static let kk_long_max_value = ExternDecl(name: "kk_long_max_value", parameterTypes: [], returnType: "intptr_t")
    static let kk_long_min_value = ExternDecl(name: "kk_long_min_value", parameterTypes: [], returnType: "intptr_t")
}
