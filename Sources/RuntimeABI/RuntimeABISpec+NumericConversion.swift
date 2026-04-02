// Numeric conversion functions (STDLIB-050).

public extension RuntimeABISpec {
    static let primitiveNumericConversionFunctions: [RuntimeABIFunctionSpec] = [
        RuntimeABIFunctionSpec(
            name: "kk_int_to_float",
            parameters: [
                RuntimeABIParameter(name: "value", type: .intptr),
            ],
            returnType: .intptr,
            section: "NumericConversion"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_int_to_byte",
            parameters: [
                RuntimeABIParameter(name: "value", type: .intptr),
            ],
            returnType: .intptr,
            section: "NumericConversion"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_int_to_short",
            parameters: [
                RuntimeABIParameter(name: "value", type: .intptr),
            ],
            returnType: .intptr,
            section: "NumericConversion"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_double_to_int",
            parameters: [
                RuntimeABIParameter(name: "value", type: .intptr),
            ],
            returnType: .intptr,
            section: "NumericConversion"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_float_to_int",
            parameters: [
                RuntimeABIParameter(name: "value", type: .intptr),
            ],
            returnType: .intptr,
            section: "NumericConversion"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_double_to_long",
            parameters: [
                RuntimeABIParameter(name: "value", type: .intptr),
            ],
            returnType: .intptr,
            section: "NumericConversion"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_float_to_long",
            parameters: [
                RuntimeABIParameter(name: "value", type: .intptr),
            ],
            returnType: .intptr,
            section: "NumericConversion"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_long_to_int",
            parameters: [
                RuntimeABIParameter(name: "value", type: .intptr),
            ],
            returnType: .intptr,
            section: "NumericConversion"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_long_to_float",
            parameters: [
                RuntimeABIParameter(name: "value", type: .intptr),
            ],
            returnType: .intptr,
            section: "NumericConversion"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_long_to_double",
            parameters: [
                RuntimeABIParameter(name: "value", type: .intptr),
            ],
            returnType: .intptr,
            section: "NumericConversion"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_double_to_float",
            parameters: [
                RuntimeABIParameter(name: "value", type: .intptr),
            ],
            returnType: .intptr,
            section: "NumericConversion"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_long_to_byte",
            parameters: [
                RuntimeABIParameter(name: "value", type: .intptr),
            ],
            returnType: .intptr,
            section: "NumericConversion"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_long_to_short",
            parameters: [
                RuntimeABIParameter(name: "value", type: .intptr),
            ],
            returnType: .intptr,
            section: "NumericConversion"
        ),
        // UByte and UShort conversions (STDLIB-PRIM-002)
        RuntimeABIFunctionSpec(
            name: "kk_int_to_ubyte",
            parameters: [
                RuntimeABIParameter(name: "value", type: .intptr),
            ],
            returnType: .intptr,
            section: "NumericConversion"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_int_to_ushort",
            parameters: [
                RuntimeABIParameter(name: "value", type: .intptr),
            ],
            returnType: .intptr,
            section: "NumericConversion"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_long_to_ubyte",
            parameters: [
                RuntimeABIParameter(name: "value", type: .intptr),
            ],
            returnType: .intptr,
            section: "NumericConversion"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_long_to_ushort",
            parameters: [
                RuntimeABIParameter(name: "value", type: .intptr),
            ],
            returnType: .intptr,
            section: "NumericConversion"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_uint_to_ubyte",
            parameters: [
                RuntimeABIParameter(name: "value", type: .intptr),
            ],
            returnType: .intptr,
            section: "NumericConversion"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_uint_to_ushort",
            parameters: [
                RuntimeABIParameter(name: "value", type: .intptr),
            ],
            returnType: .intptr,
            section: "NumericConversion"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_ulong_to_ubyte",
            parameters: [
                RuntimeABIParameter(name: "value", type: .intptr),
            ],
            returnType: .intptr,
            section: "NumericConversion"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_ulong_to_ushort",
            parameters: [
                RuntimeABIParameter(name: "value", type: .intptr),
            ],
            returnType: .intptr,
            section: "NumericConversion"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_ubyte_to_int",
            parameters: [
                RuntimeABIParameter(name: "value", type: .intptr),
            ],
            returnType: .intptr,
            section: "NumericConversion"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_ushort_to_int",
            parameters: [
                RuntimeABIParameter(name: "value", type: .intptr),
            ],
            returnType: .intptr,
            section: "NumericConversion"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_ubyte_to_long",
            parameters: [
                RuntimeABIParameter(name: "value", type: .intptr),
            ],
            returnType: .intptr,
            section: "NumericConversion"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_ushort_to_long",
            parameters: [
                RuntimeABIParameter(name: "value", type: .intptr),
            ],
            returnType: .intptr,
            section: "NumericConversion"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_ubyte_to_uint",
            parameters: [
                RuntimeABIParameter(name: "value", type: .intptr),
            ],
            returnType: .intptr,
            section: "NumericConversion"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_ushort_to_uint",
            parameters: [
                RuntimeABIParameter(name: "value", type: .intptr),
            ],
            returnType: .intptr,
            section: "NumericConversion"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_ubyte_to_ulong",
            parameters: [
                RuntimeABIParameter(name: "value", type: .intptr),
            ],
            returnType: .intptr,
            section: "NumericConversion"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_ushort_to_ulong",
            parameters: [
                RuntimeABIParameter(name: "value", type: .intptr),
            ],
            returnType: .intptr,
            section: "NumericConversion"
        ),
        // Char conversions (STDLIB-PRIM-002)
        RuntimeABIFunctionSpec(
            name: "kk_int_to_char",
            parameters: [
                RuntimeABIParameter(name: "value", type: .intptr),
            ],
            returnType: .intptr,
            section: "NumericConversion"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_long_to_char",
            parameters: [
                RuntimeABIParameter(name: "value", type: .intptr),
            ],
            returnType: .intptr,
            section: "NumericConversion"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_uint_to_char",
            parameters: [
                RuntimeABIParameter(name: "value", type: .intptr),
            ],
            returnType: .intptr,
            section: "NumericConversion"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_ulong_to_char",
            parameters: [
                RuntimeABIParameter(name: "value", type: .intptr),
            ],
            returnType: .intptr,
            section: "NumericConversion"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_ubyte_to_char",
            parameters: [
                RuntimeABIParameter(name: "value", type: .intptr),
            ],
            returnType: .intptr,
            section: "NumericConversion"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_ushort_to_char",
            parameters: [
                RuntimeABIParameter(name: "value", type: .intptr),
            ],
            returnType: .intptr,
            section: "NumericConversion"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_char_to_int",
            parameters: [
                RuntimeABIParameter(name: "value", type: .intptr),
            ],
            returnType: .intptr,
            section: "NumericConversion"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_char_to_long",
            parameters: [
                RuntimeABIParameter(name: "value", type: .intptr),
            ],
            returnType: .intptr,
            section: "NumericConversion"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_char_to_uint",
            parameters: [
                RuntimeABIParameter(name: "value", type: .intptr),
            ],
            returnType: .intptr,
            section: "NumericConversion"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_char_to_ulong",
            parameters: [
                RuntimeABIParameter(name: "value", type: .intptr),
            ],
            returnType: .intptr,
            section: "NumericConversion"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_int_coerceIn",
            parameters: [
                RuntimeABIParameter(name: "value", type: .intptr),
                RuntimeABIParameter(name: "minimum", type: .intptr),
                RuntimeABIParameter(name: "maximum", type: .intptr),
            ],
            returnType: .intptr,
            section: "NumericConversion"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_int_coerceAtLeast",
            parameters: [
                RuntimeABIParameter(name: "value", type: .intptr),
                RuntimeABIParameter(name: "minimum", type: .intptr),
            ],
            returnType: .intptr,
            section: "NumericConversion"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_int_coerceAtMost",
            parameters: [
                RuntimeABIParameter(name: "value", type: .intptr),
                RuntimeABIParameter(name: "maximum", type: .intptr),
            ],
            returnType: .intptr,
            section: "NumericConversion"
        ),
        // Long coercion (STDLIB-500)
        RuntimeABIFunctionSpec(
            name: "kk_long_coerceIn",
            parameters: [
                RuntimeABIParameter(name: "value", type: .intptr),
                RuntimeABIParameter(name: "minimum", type: .intptr),
                RuntimeABIParameter(name: "maximum", type: .intptr),
            ],
            returnType: .intptr,
            section: "NumericConversion"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_long_coerceAtLeast",
            parameters: [
                RuntimeABIParameter(name: "value", type: .intptr),
                RuntimeABIParameter(name: "minimum", type: .intptr),
            ],
            returnType: .intptr,
            section: "NumericConversion"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_long_coerceAtMost",
            parameters: [
                RuntimeABIParameter(name: "value", type: .intptr),
                RuntimeABIParameter(name: "maximum", type: .intptr),
            ],
            returnType: .intptr,
            section: "NumericConversion"
        ),
        // Double coercion (STDLIB-500)
        RuntimeABIFunctionSpec(
            name: "kk_double_coerceIn",
            parameters: [
                RuntimeABIParameter(name: "value", type: .intptr),
                RuntimeABIParameter(name: "minimum", type: .intptr),
                RuntimeABIParameter(name: "maximum", type: .intptr),
            ],
            returnType: .intptr,
            section: "NumericConversion"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_double_coerceAtLeast",
            parameters: [
                RuntimeABIParameter(name: "value", type: .intptr),
                RuntimeABIParameter(name: "minimum", type: .intptr),
            ],
            returnType: .intptr,
            section: "NumericConversion"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_double_coerceAtMost",
            parameters: [
                RuntimeABIParameter(name: "value", type: .intptr),
                RuntimeABIParameter(name: "maximum", type: .intptr),
            ],
            returnType: .intptr,
            section: "NumericConversion"
        ),
        // Float coercion (STDLIB-500)
        RuntimeABIFunctionSpec(
            name: "kk_float_coerceIn",
            parameters: [
                RuntimeABIParameter(name: "value", type: .intptr),
                RuntimeABIParameter(name: "minimum", type: .intptr),
                RuntimeABIParameter(name: "maximum", type: .intptr),
            ],
            returnType: .intptr,
            section: "NumericConversion"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_float_coerceAtLeast",
            parameters: [
                RuntimeABIParameter(name: "value", type: .intptr),
                RuntimeABIParameter(name: "minimum", type: .intptr),
            ],
            returnType: .intptr,
            section: "NumericConversion"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_float_coerceAtMost",
            parameters: [
                RuntimeABIParameter(name: "value", type: .intptr),
                RuntimeABIParameter(name: "maximum", type: .intptr),
            ],
            returnType: .intptr,
            section: "NumericConversion"
        ),
        // Range-based coercion functions (STDLIB-CONV-006)
        RuntimeABIFunctionSpec(
            name: "kk_int_coerceIn_range",
            parameters: [
                RuntimeABIParameter(name: "value", type: .intptr),
                RuntimeABIParameter(name: "range", type: .intptr),
            ],
            returnType: .intptr,
            section: "NumericConversion"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_int_coerceAtLeast_range",
            parameters: [
                RuntimeABIParameter(name: "value", type: .intptr),
                RuntimeABIParameter(name: "range", type: .intptr),
            ],
            returnType: .intptr,
            section: "NumericConversion"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_int_coerceAtMost_range",
            parameters: [
                RuntimeABIParameter(name: "value", type: .intptr),
                RuntimeABIParameter(name: "range", type: .intptr),
            ],
            returnType: .intptr,
            section: "NumericConversion"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_long_coerceIn_range",
            parameters: [
                RuntimeABIParameter(name: "value", type: .intptr),
                RuntimeABIParameter(name: "range", type: .intptr),
            ],
            returnType: .intptr,
            section: "NumericConversion"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_long_coerceAtLeast_range",
            parameters: [
                RuntimeABIParameter(name: "value", type: .intptr),
                RuntimeABIParameter(name: "range", type: .intptr),
            ],
            returnType: .intptr,
            section: "NumericConversion"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_long_coerceAtMost_range",
            parameters: [
                RuntimeABIParameter(name: "value", type: .intptr),
                RuntimeABIParameter(name: "range", type: .intptr),
            ],
            returnType: .intptr,
            section: "NumericConversion"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_double_coerceIn_range",
            parameters: [
                RuntimeABIParameter(name: "value", type: .intptr),
                RuntimeABIParameter(name: "range", type: .intptr),
            ],
            returnType: .intptr,
            section: "NumericConversion"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_double_coerceAtLeast_range",
            parameters: [
                RuntimeABIParameter(name: "value", type: .intptr),
                RuntimeABIParameter(name: "range", type: .intptr),
            ],
            returnType: .intptr,
            section: "NumericConversion"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_double_coerceAtMost_range",
            parameters: [
                RuntimeABIParameter(name: "value", type: .intptr),
                RuntimeABIParameter(name: "range", type: .intptr),
            ],
            returnType: .intptr,
            section: "NumericConversion"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_float_coerceIn_range",
            parameters: [
                RuntimeABIParameter(name: "value", type: .intptr),
                RuntimeABIParameter(name: "range", type: .intptr),
            ],
            returnType: .intptr,
            section: "NumericConversion"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_float_coerceAtLeast_range",
            parameters: [
                RuntimeABIParameter(name: "value", type: .intptr),
                RuntimeABIParameter(name: "range", type: .intptr),
            ],
            returnType: .intptr,
            section: "NumericConversion"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_float_coerceAtMost_range",
            parameters: [
                RuntimeABIParameter(name: "value", type: .intptr),
                RuntimeABIParameter(name: "range", type: .intptr),
            ],
            returnType: .intptr,
            section: "NumericConversion"
        ),
    ]
}
