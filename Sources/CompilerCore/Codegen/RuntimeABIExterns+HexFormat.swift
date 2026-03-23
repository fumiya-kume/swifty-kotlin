// MARK: - HexFormat (kotlin.text.HexFormat)

public extension RuntimeABIExterns {
    static let hexFormatExterns: [ExternDecl] = [
        kk_hexformat_default,
        kk_hexformat_create,
        kk_hexformat_upperCase,
        kk_hexformat_bytes,
        kk_int_toHexString,
        kk_long_toHexString,
        kk_bytearray_toHexString,
        kk_string_hexToInt,
        kk_string_hexToLong,
        kk_string_hexToByteArray,
    ]

    static let kk_hexformat_default = ExternDecl(
        name: "kk_hexformat_default",
        parameterTypes: [],
        returnType: "intptr_t"
    )

    static let kk_hexformat_create = ExternDecl(
        name: "kk_hexformat_create",
        parameterTypes: ["intptr_t", "intptr_t", "intptr_t * _Nullable"],
        returnType: "intptr_t"
    )

    static let kk_hexformat_upperCase = ExternDecl(
        name: "kk_hexformat_upperCase",
        parameterTypes: ["intptr_t"],
        returnType: "intptr_t"
    )

    static let kk_hexformat_bytes = ExternDecl(
        name: "kk_hexformat_bytes",
        parameterTypes: ["intptr_t"],
        returnType: "intptr_t"
    )

    static let kk_int_toHexString = ExternDecl(
        name: "kk_int_toHexString",
        parameterTypes: ["intptr_t", "intptr_t"],
        returnType: "intptr_t"
    )

    static let kk_long_toHexString = ExternDecl(
        name: "kk_long_toHexString",
        parameterTypes: ["intptr_t", "intptr_t"],
        returnType: "intptr_t"
    )

    static let kk_bytearray_toHexString = ExternDecl(
        name: "kk_bytearray_toHexString",
        parameterTypes: ["intptr_t", "intptr_t"],
        returnType: "intptr_t"
    )

    static let kk_string_hexToInt = ExternDecl(
        name: "kk_string_hexToInt",
        parameterTypes: ["intptr_t", "intptr_t"],
        returnType: "intptr_t"
    )

    static let kk_string_hexToLong = ExternDecl(
        name: "kk_string_hexToLong",
        parameterTypes: ["intptr_t", "intptr_t"],
        returnType: "intptr_t"
    )

    static let kk_string_hexToByteArray = ExternDecl(
        name: "kk_string_hexToByteArray",
        parameterTypes: ["intptr_t", "intptr_t"],
        returnType: "intptr_t"
    )
}
