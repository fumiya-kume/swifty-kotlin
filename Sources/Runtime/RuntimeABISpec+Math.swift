// Math functions (STDLIB-052).

public extension RuntimeABISpec {
    static let mathFunctions: [RuntimeABIFunctionSpec] = [
        RuntimeABIFunctionSpec(
            name: "kk_math_abs_int",
            parameters: [
                RuntimeABIParameter(name: "value", type: .intptr),
            ],
            returnType: .intptr,
            section: "Math"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_math_abs",
            parameters: [
                RuntimeABIParameter(name: "value", type: .intptr),
            ],
            returnType: .intptr,
            section: "Math"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_math_sqrt",
            parameters: [
                RuntimeABIParameter(name: "value", type: .intptr),
            ],
            returnType: .intptr,
            section: "Math"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_math_pow",
            parameters: [
                RuntimeABIParameter(name: "base", type: .intptr),
                RuntimeABIParameter(name: "exp", type: .intptr),
            ],
            returnType: .intptr,
            section: "Math"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_math_ceil",
            parameters: [
                RuntimeABIParameter(name: "value", type: .intptr),
            ],
            returnType: .intptr,
            section: "Math"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_math_floor",
            parameters: [
                RuntimeABIParameter(name: "value", type: .intptr),
            ],
            returnType: .intptr,
            section: "Math"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_math_round",
            parameters: [
                RuntimeABIParameter(name: "value", type: .intptr),
            ],
            returnType: .intptr,
            section: "Math"
        ),
        // Trigonometric functions (STDLIB-430)
        RuntimeABIFunctionSpec(
            name: "kk_math_sin",
            parameters: [
                RuntimeABIParameter(name: "value", type: .intptr),
            ],
            returnType: .intptr,
            section: "Math"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_math_cos",
            parameters: [
                RuntimeABIParameter(name: "value", type: .intptr),
            ],
            returnType: .intptr,
            section: "Math"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_math_tan",
            parameters: [
                RuntimeABIParameter(name: "value", type: .intptr),
            ],
            returnType: .intptr,
            section: "Math"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_math_asin",
            parameters: [
                RuntimeABIParameter(name: "value", type: .intptr),
            ],
            returnType: .intptr,
            section: "Math"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_math_acos",
            parameters: [
                RuntimeABIParameter(name: "value", type: .intptr),
            ],
            returnType: .intptr,
            section: "Math"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_math_atan",
            parameters: [
                RuntimeABIParameter(name: "value", type: .intptr),
            ],
            returnType: .intptr,
            section: "Math"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_math_atan2",
            parameters: [
                RuntimeABIParameter(name: "y", type: .intptr),
                RuntimeABIParameter(name: "x", type: .intptr),
            ],
            returnType: .intptr,
            section: "Math"
        ),
    ]
}
