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
}
