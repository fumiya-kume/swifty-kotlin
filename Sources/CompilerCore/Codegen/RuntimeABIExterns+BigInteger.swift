// MARK: - BigInteger (STDLIB-NUM-129)

public extension RuntimeABIExterns {
    static let bigIntegerExterns: [ExternDecl] = [
        kk_biginteger_valueOf,
        kk_biginteger_fromString,
        kk_biginteger_add,
        kk_biginteger_subtract,
        kk_biginteger_multiply,
        kk_biginteger_divide,
        kk_biginteger_gcd,
        kk_biginteger_abs,
        kk_biginteger_pow,
        kk_biginteger_toInt,
        kk_biginteger_toLong,
        kk_biginteger_toString,
    ]

    static let kk_biginteger_valueOf = ExternDecl(
        name: "kk_biginteger_valueOf",
        parameterTypes: ["intptr_t"],
        returnType: "intptr_t"
    )

    static let kk_biginteger_fromString = ExternDecl(
        name: "kk_biginteger_fromString",
        parameterTypes: ["intptr_t", "intptr_t * _Nullable"],
        returnType: "intptr_t"
    )

    static let kk_biginteger_add = ExternDecl(
        name: "kk_biginteger_add",
        parameterTypes: ["intptr_t", "intptr_t"],
        returnType: "intptr_t"
    )

    static let kk_biginteger_subtract = ExternDecl(
        name: "kk_biginteger_subtract",
        parameterTypes: ["intptr_t", "intptr_t"],
        returnType: "intptr_t"
    )

    static let kk_biginteger_multiply = ExternDecl(
        name: "kk_biginteger_multiply",
        parameterTypes: ["intptr_t", "intptr_t"],
        returnType: "intptr_t"
    )

    static let kk_biginteger_divide = ExternDecl(
        name: "kk_biginteger_divide",
        parameterTypes: ["intptr_t", "intptr_t", "intptr_t * _Nullable"],
        returnType: "intptr_t"
    )

    static let kk_biginteger_gcd = ExternDecl(
        name: "kk_biginteger_gcd",
        parameterTypes: ["intptr_t", "intptr_t"],
        returnType: "intptr_t"
    )

    static let kk_biginteger_abs = ExternDecl(
        name: "kk_biginteger_abs",
        parameterTypes: ["intptr_t"],
        returnType: "intptr_t"
    )

    static let kk_biginteger_pow = ExternDecl(
        name: "kk_biginteger_pow",
        parameterTypes: ["intptr_t", "intptr_t", "intptr_t * _Nullable"],
        returnType: "intptr_t"
    )

    static let kk_biginteger_toInt = ExternDecl(
        name: "kk_biginteger_toInt",
        parameterTypes: ["intptr_t"],
        returnType: "intptr_t"
    )

    static let kk_biginteger_toLong = ExternDecl(
        name: "kk_biginteger_toLong",
        parameterTypes: ["intptr_t"],
        returnType: "intptr_t"
    )

    static let kk_biginteger_toString = ExternDecl(
        name: "kk_biginteger_toString",
        parameterTypes: ["intptr_t"],
        returnType: "intptr_t"
    )
}
