// MARK: - Numeric Conversion

public extension RuntimeABIExterns {
    static let primitiveNumericConversionExterns: [ExternDecl] = [
        kk_int_to_float,
        kk_int_to_byte,
        kk_int_to_short,
        kk_double_to_int,
        kk_float_to_int,
        kk_double_to_long,
        kk_float_to_long,
        kk_long_to_float,
        kk_long_to_double,
        kk_double_to_float,
        kk_long_to_byte,
        kk_long_to_short,
        kk_int_coerceIn,
        kk_int_coerceAtLeast,
        kk_int_coerceAtMost,
    ]

    static let kk_int_to_float = ExternDecl(
        name: "kk_int_to_float",
        parameterTypes: ["intptr_t"],
        returnType: "intptr_t"
    )

    static let kk_int_to_byte = ExternDecl(
        name: "kk_int_to_byte",
        parameterTypes: ["intptr_t"],
        returnType: "intptr_t"
    )

    static let kk_int_to_short = ExternDecl(
        name: "kk_int_to_short",
        parameterTypes: ["intptr_t"],
        returnType: "intptr_t"
    )

    static let kk_double_to_int = ExternDecl(
        name: "kk_double_to_int",
        parameterTypes: ["intptr_t"],
        returnType: "intptr_t"
    )

    static let kk_float_to_int = ExternDecl(
        name: "kk_float_to_int",
        parameterTypes: ["intptr_t"],
        returnType: "intptr_t"
    )

    static let kk_double_to_long = ExternDecl(
        name: "kk_double_to_long",
        parameterTypes: ["intptr_t"],
        returnType: "intptr_t"
    )

    static let kk_float_to_long = ExternDecl(
        name: "kk_float_to_long",
        parameterTypes: ["intptr_t"],
        returnType: "intptr_t"
    )

    static let kk_long_to_float = ExternDecl(
        name: "kk_long_to_float",
        parameterTypes: ["intptr_t"],
        returnType: "intptr_t"
    )

    static let kk_long_to_double = ExternDecl(
        name: "kk_long_to_double",
        parameterTypes: ["intptr_t"],
        returnType: "intptr_t"
    )

    static let kk_double_to_float = ExternDecl(
        name: "kk_double_to_float",
        parameterTypes: ["intptr_t"],
        returnType: "intptr_t"
    )

    static let kk_long_to_byte = ExternDecl(
        name: "kk_long_to_byte",
        parameterTypes: ["intptr_t"],
        returnType: "intptr_t"
    )

    static let kk_long_to_short = ExternDecl(
        name: "kk_long_to_short",
        parameterTypes: ["intptr_t"],
        returnType: "intptr_t"
    )

    static let kk_int_coerceIn = ExternDecl(
        name: "kk_int_coerceIn",
        parameterTypes: ["intptr_t", "intptr_t", "intptr_t"],
        returnType: "intptr_t"
    )

    static let kk_int_coerceAtLeast = ExternDecl(
        name: "kk_int_coerceAtLeast",
        parameterTypes: ["intptr_t", "intptr_t"],
        returnType: "intptr_t"
    )

    static let kk_int_coerceAtMost = ExternDecl(
        name: "kk_int_coerceAtMost",
        parameterTypes: ["intptr_t", "intptr_t"],
        returnType: "intptr_t"
    )
}
