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
}
