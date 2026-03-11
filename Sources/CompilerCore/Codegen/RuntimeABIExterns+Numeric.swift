// MARK: - Numeric Conversion

public extension RuntimeABIExterns {
    static let primitiveNumericConversionExterns: [ExternDecl] = [
        kk_int_to_float,
        kk_int_to_byte,
        kk_int_to_short,
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
}
