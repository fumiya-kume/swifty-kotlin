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
    ]
}
