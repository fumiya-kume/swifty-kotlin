// Numeric conversion functions (STDLIB-050).

public extension RuntimeABISpec {
    static let primitiveNumericConversionFunctions: [RuntimeABIFunctionSpec] = [
        RuntimeABIFunctionSpec(
            name: "kk_int_to_float",
            parameters: [
                RuntimeABIParameter(name: "value", type: .intptr),
            ],
            returnType: .intptr,
            section: "NumericConversion",
            isThrowing: false
        ),
        RuntimeABIFunctionSpec(
            name: "kk_int_to_byte",
            parameters: [
                RuntimeABIParameter(name: "value", type: .intptr),
            ],
            returnType: .intptr,
            section: "NumericConversion",
            isThrowing: false
        ),
        RuntimeABIFunctionSpec(
            name: "kk_int_to_short",
            parameters: [
                RuntimeABIParameter(name: "value", type: .intptr),
            ],
            returnType: .intptr,
            section: "NumericConversion",
            isThrowing: false
        ),
        RuntimeABIFunctionSpec(
            name: "kk_long_to_int",
            parameters: [
                RuntimeABIParameter(name: "value", type: .intptr),
            ],
            returnType: .intptr,
            section: "NumericConversion",
            isThrowing: false
        ),
        RuntimeABIFunctionSpec(
            name: "kk_long_to_float",
            parameters: [
                RuntimeABIParameter(name: "value", type: .intptr),
            ],
            returnType: .intptr,
            section: "NumericConversion",
            isThrowing: false
        ),
        RuntimeABIFunctionSpec(
            name: "kk_long_to_double",
            parameters: [
                RuntimeABIParameter(name: "value", type: .intptr),
            ],
            returnType: .intptr,
            section: "NumericConversion",
            isThrowing: false
        ),
        RuntimeABIFunctionSpec(
            name: "kk_double_to_float",
            parameters: [
                RuntimeABIParameter(name: "value", type: .intptr),
            ],
            returnType: .intptr,
            section: "NumericConversion",
            isThrowing: false
        ),
        RuntimeABIFunctionSpec(
            name: "kk_long_to_byte",
            parameters: [
                RuntimeABIParameter(name: "value", type: .intptr),
            ],
            returnType: .intptr,
            section: "NumericConversion",
            isThrowing: false
        ),
        RuntimeABIFunctionSpec(
            name: "kk_long_to_short",
            parameters: [
                RuntimeABIParameter(name: "value", type: .intptr),
            ],
            returnType: .intptr,
            section: "NumericConversion",
            isThrowing: false
        ),
        // UByte and UShort conversions (STDLIB-PRIM-002)
        RuntimeABIFunctionSpec(
            name: "kk_int_to_ubyte",
            parameters: [
                RuntimeABIParameter(name: "value", type: .intptr),
            ],
            returnType: .intptr,
            section: "NumericConversion",
            isThrowing: false
        ),
        RuntimeABIFunctionSpec(
            name: "kk_int_to_ushort",
            parameters: [
                RuntimeABIParameter(name: "value", type: .intptr),
            ],
            returnType: .intptr,
            section: "NumericConversion",
            isThrowing: false
        ),
        RuntimeABIFunctionSpec(
            name: "kk_long_to_ubyte",
            parameters: [
                RuntimeABIParameter(name: "value", type: .intptr),
            ],
            returnType: .intptr,
            section: "NumericConversion",
            isThrowing: false
        ),
        RuntimeABIFunctionSpec(
            name: "kk_long_to_ushort",
            parameters: [
                RuntimeABIParameter(name: "value", type: .intptr),
            ],
            returnType: .intptr,
            section: "NumericConversion",
            isThrowing: false
        ),
        RuntimeABIFunctionSpec(
            name: "kk_uint_to_ubyte",
            parameters: [
                RuntimeABIParameter(name: "value", type: .intptr),
            ],
            returnType: .intptr,
            section: "NumericConversion",
            isThrowing: false
        ),
        RuntimeABIFunctionSpec(
            name: "kk_uint_to_ushort",
            parameters: [
                RuntimeABIParameter(name: "value", type: .intptr),
            ],
            returnType: .intptr,
            section: "NumericConversion",
            isThrowing: false
        ),
        RuntimeABIFunctionSpec(
            name: "kk_ulong_to_ubyte",
            parameters: [
                RuntimeABIParameter(name: "value", type: .intptr),
            ],
            returnType: .intptr,
            section: "NumericConversion",
            isThrowing: false
        ),
        RuntimeABIFunctionSpec(
            name: "kk_ulong_to_ushort",
            parameters: [
                RuntimeABIParameter(name: "value", type: .intptr),
            ],
            returnType: .intptr,
            section: "NumericConversion",
            isThrowing: false
        ),
        RuntimeABIFunctionSpec(
            name: "kk_ubyte_to_int",
            parameters: [
                RuntimeABIParameter(name: "value", type: .intptr),
            ],
            returnType: .intptr,
            section: "NumericConversion",
            isThrowing: false
        ),
        RuntimeABIFunctionSpec(
            name: "kk_ushort_to_int",
            parameters: [
                RuntimeABIParameter(name: "value", type: .intptr),
            ],
            returnType: .intptr,
            section: "NumericConversion",
            isThrowing: false
        ),
        RuntimeABIFunctionSpec(
            name: "kk_ubyte_to_long",
            parameters: [
                RuntimeABIParameter(name: "value", type: .intptr),
            ],
            returnType: .intptr,
            section: "NumericConversion",
            isThrowing: false
        ),
        RuntimeABIFunctionSpec(
            name: "kk_ushort_to_long",
            parameters: [
                RuntimeABIParameter(name: "value", type: .intptr),
            ],
            returnType: .intptr,
            section: "NumericConversion",
            isThrowing: false
        ),
        RuntimeABIFunctionSpec(
            name: "kk_ubyte_to_uint",
            parameters: [
                RuntimeABIParameter(name: "value", type: .intptr),
            ],
            returnType: .intptr,
            section: "NumericConversion",
            isThrowing: false
        ),
        RuntimeABIFunctionSpec(
            name: "kk_ushort_to_uint",
            parameters: [
                RuntimeABIParameter(name: "value", type: .intptr),
            ],
            returnType: .intptr,
            section: "NumericConversion",
            isThrowing: false
        ),
        RuntimeABIFunctionSpec(
            name: "kk_ubyte_to_ulong",
            parameters: [
                RuntimeABIParameter(name: "value", type: .intptr),
            ],
            returnType: .intptr,
            section: "NumericConversion",
            isThrowing: false
        ),
        RuntimeABIFunctionSpec(
            name: "kk_ushort_to_ulong",
            parameters: [
                RuntimeABIParameter(name: "value", type: .intptr),
            ],
            returnType: .intptr,
            section: "NumericConversion",
            isThrowing: false
        ),
        // Unsigned toFloat / toDouble conversions
        RuntimeABIFunctionSpec(
            name: "kk_uint_to_float",
            parameters: [
                RuntimeABIParameter(name: "value", type: .intptr),
            ],
            returnType: .intptr,
            section: "NumericConversion",
            isThrowing: true
        ),
        RuntimeABIFunctionSpec(
            name: "kk_uint_to_double",
            parameters: [
                RuntimeABIParameter(name: "value", type: .intptr),
            ],
            returnType: .intptr,
            section: "NumericConversion",
            isThrowing: true
        ),
        RuntimeABIFunctionSpec(
            name: "kk_ulong_to_float",
            parameters: [
                RuntimeABIParameter(name: "value", type: .intptr),
            ],
            returnType: .intptr,
            section: "NumericConversion",
            isThrowing: true
        ),
        RuntimeABIFunctionSpec(
            name: "kk_ulong_to_double",
            parameters: [
                RuntimeABIParameter(name: "value", type: .intptr),
            ],
            returnType: .intptr,
            section: "NumericConversion",
            isThrowing: true
        ),
        RuntimeABIFunctionSpec(
            name: "kk_ubyte_to_float",
            parameters: [
                RuntimeABIParameter(name: "value", type: .intptr),
            ],
            returnType: .intptr,
            section: "NumericConversion",
            isThrowing: true
        ),
        RuntimeABIFunctionSpec(
            name: "kk_ubyte_to_double",
            parameters: [
                RuntimeABIParameter(name: "value", type: .intptr),
            ],
            returnType: .intptr,
            section: "NumericConversion",
            isThrowing: true
        ),
        RuntimeABIFunctionSpec(
            name: "kk_ushort_to_float",
            parameters: [
                RuntimeABIParameter(name: "value", type: .intptr),
            ],
            returnType: .intptr,
            section: "NumericConversion",
            isThrowing: true
        ),
        RuntimeABIFunctionSpec(
            name: "kk_ushort_to_double",
            parameters: [
                RuntimeABIParameter(name: "value", type: .intptr),
            ],
            returnType: .intptr,
            section: "NumericConversion",
            isThrowing: true
        ),
        // UByte / UShort cross-unsigned conversions
        RuntimeABIFunctionSpec(
            name: "kk_ubyte_to_ushort",
            parameters: [
                RuntimeABIParameter(name: "value", type: .intptr),
            ],
            returnType: .intptr,
            section: "NumericConversion",
            isThrowing: true
        ),
        RuntimeABIFunctionSpec(
            name: "kk_ushort_to_ubyte",
            parameters: [
                RuntimeABIParameter(name: "value", type: .intptr),
            ],
            returnType: .intptr,
            section: "NumericConversion",
            isThrowing: true
        ),
        // SPEC-NUM-0007: unsigned toByte / toShort conversions
        RuntimeABIFunctionSpec(
            name: "kk_uint_to_byte",
            parameters: [
                RuntimeABIParameter(name: "value", type: .intptr),
            ],
            returnType: .intptr,
            section: "NumericConversion",
            isThrowing: false
        ),
        RuntimeABIFunctionSpec(
            name: "kk_uint_to_short",
            parameters: [
                RuntimeABIParameter(name: "value", type: .intptr),
            ],
            returnType: .intptr,
            section: "NumericConversion",
            isThrowing: false
        ),
        RuntimeABIFunctionSpec(
            name: "kk_ulong_to_byte",
            parameters: [
                RuntimeABIParameter(name: "value", type: .intptr),
            ],
            returnType: .intptr,
            section: "NumericConversion",
            isThrowing: false
        ),
        RuntimeABIFunctionSpec(
            name: "kk_ulong_to_short",
            parameters: [
                RuntimeABIParameter(name: "value", type: .intptr),
            ],
            returnType: .intptr,
            section: "NumericConversion",
            isThrowing: false
        ),
        RuntimeABIFunctionSpec(
            name: "kk_ubyte_to_byte",
            parameters: [
                RuntimeABIParameter(name: "value", type: .intptr),
            ],
            returnType: .intptr,
            section: "NumericConversion",
            isThrowing: false
        ),
        RuntimeABIFunctionSpec(
            name: "kk_ubyte_to_short",
            parameters: [
                RuntimeABIParameter(name: "value", type: .intptr),
            ],
            returnType: .intptr,
            section: "NumericConversion",
            isThrowing: false
        ),
        RuntimeABIFunctionSpec(
            name: "kk_ushort_to_byte",
            parameters: [
                RuntimeABIParameter(name: "value", type: .intptr),
            ],
            returnType: .intptr,
            section: "NumericConversion",
            isThrowing: false
        ),
        RuntimeABIFunctionSpec(
            name: "kk_ushort_to_short",
            parameters: [
                RuntimeABIParameter(name: "value", type: .intptr),
            ],
            returnType: .intptr,
            section: "NumericConversion",
            isThrowing: false
        ),
        // Char conversions (STDLIB-PRIM-002)
        RuntimeABIFunctionSpec(
            name: "kk_int_to_char",
            parameters: [
                RuntimeABIParameter(name: "value", type: .intptr),
            ],
            returnType: .intptr,
            section: "NumericConversion",
            isThrowing: false
        ),
        RuntimeABIFunctionSpec(
            name: "kk_uint_to_char",
            parameters: [
                RuntimeABIParameter(name: "value", type: .intptr),
            ],
            returnType: .intptr,
            section: "NumericConversion",
            isThrowing: false
        ),
        RuntimeABIFunctionSpec(
            name: "kk_ulong_to_char",
            parameters: [
                RuntimeABIParameter(name: "value", type: .intptr),
            ],
            returnType: .intptr,
            section: "NumericConversion",
            isThrowing: false
        ),
        RuntimeABIFunctionSpec(
            name: "kk_ubyte_to_char",
            parameters: [
                RuntimeABIParameter(name: "value", type: .intptr),
            ],
            returnType: .intptr,
            section: "NumericConversion",
            isThrowing: false
        ),
        RuntimeABIFunctionSpec(
            name: "kk_ushort_to_char",
            parameters: [
                RuntimeABIParameter(name: "value", type: .intptr),
            ],
            returnType: .intptr,
            section: "NumericConversion",
            isThrowing: false
        ),
        // KSP-1540 / DEBT-DIFF-008: Number.toDouble/toFloat/toLong/toInt/
        // toShort/toByte dispatch for an erased `Number`/`T : Number`
        // receiver — see CallLowerer+NumberConversionMemberCalls.swift and
        // Sources/Runtime/RuntimeNumberConversionDispatch.swift.
        RuntimeABIFunctionSpec(
            name: "kk_number_to_primitive",
            parameters: [
                RuntimeABIParameter(name: "receiver", type: .intptr),
                RuntimeABIParameter(name: "slot", type: .intptr),
                RuntimeABIParameter(name: "targetKindRaw", type: .int32),
            ],
            returnType: .intptr,
            section: "NumericConversion",
            isThrowing: false
        ),
    ]
}
