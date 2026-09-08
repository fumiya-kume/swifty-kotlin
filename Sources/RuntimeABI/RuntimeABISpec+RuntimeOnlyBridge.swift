private let arraySpecialBridgeFunctions: [RuntimeABIFunctionSpec] = [
    RuntimeABIFunctionSpec(
        name: "kk_bits_to_double",
        parameters: [RuntimeABIParameter(name: "value", type: .intptr)],
        returnType: .double,
        section: "NumericConversion"
    ),
    RuntimeABIFunctionSpec(
        name: "kk_bits_to_float",
        parameters: [RuntimeABIParameter(name: "value", type: .intptr)],
        returnType: .float,
        section: "NumericConversion"
    ),
    RuntimeABIFunctionSpec(
        name: "kk_double_to_bits",
        parameters: [RuntimeABIParameter(name: "value", type: .double)],
        returnType: .intptr,
        section: "NumericConversion"
    ),
    RuntimeABIFunctionSpec(
        name: "kk_float_to_bits",
        parameters: [RuntimeABIParameter(name: "value", type: .float)],
        returnType: .intptr,
        section: "NumericConversion"
    ),
]

private let numericOnlyBridgeFunctions: [RuntimeABIFunctionSpec] =
    ["kk_byte_to_char", "kk_byte_to_uint", "kk_byte_to_ulong",
     "kk_short_to_char", "kk_short_to_uint", "kk_short_to_ulong"].map {
        bridgeSpec($0, section: "NumericConversion", params: ["value"])
    }

private let minMaxFloatDoubleBridgeFunctions: [RuntimeABIFunctionSpec] =
    ["kk_min_float", "kk_max_float", "kk_min_double", "kk_max_double"].map {
        bridgeSpec(
            $0,
            section: "NumericConversion",
            typedParams: [
                ("aBits", .intptr),
                ("bBits", .intptr),
            ],
            returnType: .intptr,
            isThrowing: false
        )
    }

private let coroutineOnlyBridgeFunctions: [RuntimeABIFunctionSpec] = [
    bridgeSpec("__kk_flow_stopped", section: "Coroutine"),
    bridgeSpec("kk_supervisor_scope_new", section: "Coroutine"),
]

private let kclassBridgeFunctions = [
    "__kk_kclass_get_arity",
].map { bridgeSpec($0, section: "TypeCheck", params: ["kclassRaw"]) }

public extension RuntimeABISpec {
    static let runtimeOnlyBridgeFunctions: [RuntimeABIFunctionSpec] =
        arraySpecialBridgeFunctions
        + numericOnlyBridgeFunctions
        + minMaxFloatDoubleBridgeFunctions
        + coroutineOnlyBridgeFunctions
        + kclassBridgeFunctions
}
