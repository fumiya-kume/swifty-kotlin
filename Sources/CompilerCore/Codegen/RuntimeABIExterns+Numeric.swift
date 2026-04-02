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
        kk_long_to_int,
        kk_long_to_float,
        kk_long_to_double,
        kk_double_to_float,
        kk_long_to_byte,
        kk_long_to_short,
        // UByte and UShort conversions (STDLIB-PRIM-002)
        kk_int_to_ubyte,
        kk_int_to_ushort,
        kk_long_to_ubyte,
        kk_long_to_ushort,
        kk_uint_to_ubyte,
        kk_uint_to_ushort,
        kk_ulong_to_ubyte,
        kk_ulong_to_ushort,
        kk_ubyte_to_int,
        kk_ushort_to_int,
        kk_ubyte_to_long,
        kk_ushort_to_long,
        kk_ubyte_to_uint,
        kk_ushort_to_uint,
        kk_ubyte_to_ulong,
        kk_ushort_to_ulong,
        // Char conversions (STDLIB-PRIM-002)
        kk_int_to_char,
        kk_long_to_char,
        kk_uint_to_char,
        kk_ulong_to_char,
        kk_ubyte_to_char,
        kk_ushort_to_char,
        kk_char_to_int,
        kk_char_to_long,
        kk_char_to_uint,
        kk_char_to_ulong,
        // Coercion functions
        kk_int_coerceIn,
        kk_int_coerceAtLeast,
        kk_int_coerceAtMost,
        kk_long_coerceIn,
        kk_long_coerceAtLeast,
        kk_long_coerceAtMost,
        kk_double_coerceIn,
        kk_double_coerceAtLeast,
        kk_double_coerceAtMost,
        kk_float_coerceIn,
        kk_float_coerceAtLeast,
        kk_float_coerceAtMost,
        // STDLIB-NUM-130: isNaN / isInfinite / isFinite / toBits / toRawBits / fromBits
        kk_double_isNaN,
        kk_double_isInfinite,
        kk_double_isFinite,
        kk_float_isNaN,
        kk_float_isInfinite,
        kk_float_isFinite,
        kk_double_toBits,
        kk_double_toRawBits,
        kk_double_fromBits,
        kk_float_toBits,
        kk_float_toRawBits,
        kk_float_fromBits,
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

    static let kk_long_to_int = ExternDecl(
        name: "kk_long_to_int",
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

    // Long coercion (STDLIB-500)
    static let kk_long_coerceIn = ExternDecl(
        name: "kk_long_coerceIn",
        parameterTypes: ["intptr_t", "intptr_t", "intptr_t"],
        returnType: "intptr_t"
    )

    static let kk_long_coerceAtLeast = ExternDecl(
        name: "kk_long_coerceAtLeast",
        parameterTypes: ["intptr_t", "intptr_t"],
        returnType: "intptr_t"
    )

    static let kk_long_coerceAtMost = ExternDecl(
        name: "kk_long_coerceAtMost",
        parameterTypes: ["intptr_t", "intptr_t"],
        returnType: "intptr_t"
    )

    // Double coercion (STDLIB-500)
    static let kk_double_coerceIn = ExternDecl(
        name: "kk_double_coerceIn",
        parameterTypes: ["intptr_t", "intptr_t", "intptr_t"],
        returnType: "intptr_t"
    )

    static let kk_double_coerceAtLeast = ExternDecl(
        name: "kk_double_coerceAtLeast",
        parameterTypes: ["intptr_t", "intptr_t"],
        returnType: "intptr_t"
    )

    static let kk_double_coerceAtMost = ExternDecl(
        name: "kk_double_coerceAtMost",
        parameterTypes: ["intptr_t", "intptr_t"],
        returnType: "intptr_t"
    )

    // Float coercion (STDLIB-500)
    static let kk_float_coerceIn = ExternDecl(
        name: "kk_float_coerceIn",
        parameterTypes: ["intptr_t", "intptr_t", "intptr_t"],
        returnType: "intptr_t"
    )

    static let kk_float_coerceAtLeast = ExternDecl(
        name: "kk_float_coerceAtLeast",
        parameterTypes: ["intptr_t", "intptr_t"],
        returnType: "intptr_t"
    )

    static let kk_float_coerceAtMost = ExternDecl(
        name: "kk_float_coerceAtMost",
        parameterTypes: ["intptr_t", "intptr_t"],
        returnType: "intptr_t"
    )

    // MARK: - UByte and UShort Conversions (STDLIB-PRIM-002)

    static let kk_int_to_ubyte = ExternDecl(
        name: "kk_int_to_ubyte",
        parameterTypes: ["intptr_t"],
        returnType: "intptr_t"
    )

    static let kk_int_to_ushort = ExternDecl(
        name: "kk_int_to_ushort",
        parameterTypes: ["intptr_t"],
        returnType: "intptr_t"
    )

    static let kk_long_to_ubyte = ExternDecl(
        name: "kk_long_to_ubyte",
        parameterTypes: ["intptr_t"],
        returnType: "intptr_t"
    )

    static let kk_long_to_ushort = ExternDecl(
        name: "kk_long_to_ushort",
        parameterTypes: ["intptr_t"],
        returnType: "intptr_t"
    )

    static let kk_uint_to_ubyte = ExternDecl(
        name: "kk_uint_to_ubyte",
        parameterTypes: ["intptr_t"],
        returnType: "intptr_t"
    )

    static let kk_uint_to_ushort = ExternDecl(
        name: "kk_uint_to_ushort",
        parameterTypes: ["intptr_t"],
        returnType: "intptr_t"
    )

    static let kk_ulong_to_ubyte = ExternDecl(
        name: "kk_ulong_to_ubyte",
        parameterTypes: ["intptr_t"],
        returnType: "intptr_t"
    )

    static let kk_ulong_to_ushort = ExternDecl(
        name: "kk_ulong_to_ushort",
        parameterTypes: ["intptr_t"],
        returnType: "intptr_t"
    )

    static let kk_ubyte_to_int = ExternDecl(
        name: "kk_ubyte_to_int",
        parameterTypes: ["intptr_t"],
        returnType: "intptr_t"
    )

    static let kk_ushort_to_int = ExternDecl(
        name: "kk_ushort_to_int",
        parameterTypes: ["intptr_t"],
        returnType: "intptr_t"
    )

    static let kk_ubyte_to_long = ExternDecl(
        name: "kk_ubyte_to_long",
        parameterTypes: ["intptr_t"],
        returnType: "intptr_t"
    )

    static let kk_ushort_to_long = ExternDecl(
        name: "kk_ushort_to_long",
        parameterTypes: ["intptr_t"],
        returnType: "intptr_t"
    )

    static let kk_ubyte_to_uint = ExternDecl(
        name: "kk_ubyte_to_uint",
        parameterTypes: ["intptr_t"],
        returnType: "intptr_t"
    )

    static let kk_ushort_to_uint = ExternDecl(
        name: "kk_ushort_to_uint",
        parameterTypes: ["intptr_t"],
        returnType: "intptr_t"
    )

    static let kk_ubyte_to_ulong = ExternDecl(
        name: "kk_ubyte_to_ulong",
        parameterTypes: ["intptr_t"],
        returnType: "intptr_t"
    )

    static let kk_ushort_to_ulong = ExternDecl(
        name: "kk_ushort_to_ulong",
        parameterTypes: ["intptr_t"],
        returnType: "intptr_t"
    )

    // MARK: - Char Conversions (STDLIB-PRIM-002)

    static let kk_int_to_char = ExternDecl(
        name: "kk_int_to_char",
        parameterTypes: ["intptr_t"],
        returnType: "intptr_t"
    )

    static let kk_long_to_char = ExternDecl(
        name: "kk_long_to_char",
        parameterTypes: ["intptr_t"],
        returnType: "intptr_t"
    )

    static let kk_uint_to_char = ExternDecl(
        name: "kk_uint_to_char",
        parameterTypes: ["intptr_t"],
        returnType: "intptr_t"
    )

    static let kk_ulong_to_char = ExternDecl(
        name: "kk_ulong_to_char",
        parameterTypes: ["intptr_t"],
        returnType: "intptr_t"
    )

    static let kk_ubyte_to_char = ExternDecl(
        name: "kk_ubyte_to_char",
        parameterTypes: ["intptr_t"],
        returnType: "intptr_t"
    )

    static let kk_ushort_to_char = ExternDecl(
        name: "kk_ushort_to_char",
        parameterTypes: ["intptr_t"],
        returnType: "intptr_t"
    )

    static let kk_char_to_int = ExternDecl(
        name: "kk_char_to_int",
        parameterTypes: ["intptr_t"],
        returnType: "intptr_t"
    )

    static let kk_char_to_long = ExternDecl(
        name: "kk_char_to_long",
        parameterTypes: ["intptr_t"],
        returnType: "intptr_t"
    )

    static let kk_char_to_uint = ExternDecl(
        name: "kk_char_to_uint",
        parameterTypes: ["intptr_t"],
        returnType: "intptr_t"
    )

    static let kk_char_to_ulong = ExternDecl(
        name: "kk_char_to_ulong",
        parameterTypes: ["intptr_t"],
        returnType: "intptr_t"
    )

    // MARK: - STDLIB-NUM-130: Floating-point precision predicates and bit-conversion

    static let kk_double_isNaN = ExternDecl(name: "kk_double_isNaN", parameterTypes: ["intptr_t"], returnType: "intptr_t")
    static let kk_double_isInfinite = ExternDecl(name: "kk_double_isInfinite", parameterTypes: ["intptr_t"], returnType: "intptr_t")
    static let kk_double_isFinite = ExternDecl(name: "kk_double_isFinite", parameterTypes: ["intptr_t"], returnType: "intptr_t")
    static let kk_float_isNaN = ExternDecl(name: "kk_float_isNaN", parameterTypes: ["intptr_t"], returnType: "intptr_t")
    static let kk_float_isInfinite = ExternDecl(name: "kk_float_isInfinite", parameterTypes: ["intptr_t"], returnType: "intptr_t")
    static let kk_float_isFinite = ExternDecl(name: "kk_float_isFinite", parameterTypes: ["intptr_t"], returnType: "intptr_t")
    static let kk_double_toBits = ExternDecl(name: "kk_double_toBits", parameterTypes: ["intptr_t"], returnType: "intptr_t")
    static let kk_double_toRawBits = ExternDecl(name: "kk_double_toRawBits", parameterTypes: ["intptr_t"], returnType: "intptr_t")
    static let kk_double_fromBits = ExternDecl(name: "kk_double_fromBits", parameterTypes: ["intptr_t"], returnType: "intptr_t")
    static let kk_float_toBits = ExternDecl(name: "kk_float_toBits", parameterTypes: ["intptr_t"], returnType: "intptr_t")
    static let kk_float_toRawBits = ExternDecl(name: "kk_float_toRawBits", parameterTypes: ["intptr_t"], returnType: "intptr_t")
    static let kk_float_fromBits = ExternDecl(name: "kk_float_fromBits", parameterTypes: ["intptr_t"], returnType: "intptr_t")
}
