private let arrayHOFBridgeNames = [
    "kk_array_all",
    "kk_array_count",
    "kk_array_filterIndexed",
    "kk_array_filterNot",
    "kk_array_find",
    "kk_array_findLast",
    "kk_array_first",
    "kk_array_firstOrNull",
    "kk_array_flatMap",
    "kk_array_last",
    "kk_array_lastOrNull",
    "kk_array_mapIndexed",
    "kk_array_mapNotNull",
    "kk_array_reduce",
    "kk_array_reduceIndexed",
    "kk_array_reduceOrNull",
]

private let arrayHOFBridgeFunctions = arrayHOFBridgeNames.map {
    bridgeSpec(
        $0,
        section: "Collection",
        typedParams: [
            ("arrayRaw", .intptr),
            ("fnPtr", .intptr),
            ("closureRaw", .intptr),
            ("outThrown", .nullableIntptrPointer),
        ]
    )
}

private let arrayFoldBridgeFunctions = [
    "kk_array_fold",
    "kk_array_foldIndexed",
].map {
    bridgeSpec(
        $0,
        section: "Collection",
        typedParams: [
            ("arrayRaw", .intptr),
            ("initial", .intptr),
            ("fnPtr", .intptr),
            ("closureRaw", .intptr),
            ("outThrown", .nullableIntptrPointer),
        ]
    )
}

private let arraySpecialBridgeFunctions: [RuntimeABIFunctionSpec] = [
    bridgeSpec("kk_array_filterNotNull", section: "Collection", params: ["arrayRaw"]),
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

private let coroutineOnlyBridgeFunctions: [RuntimeABIFunctionSpec] = [
    bridgeSpec("kk_flow_stopped", section: "Coroutine"),
    bridgeSpec("kk_kxmini_run_loop", section: "Coroutine", params: ["entryPointRaw", "functionID"]),
    bridgeSpec("kk_supervisor_scope_new", section: "Coroutine"),
]

private let kclassBridgeFunctions = [
    "kk_kclass_get_arity",
    "kk_kclass_get_field_count",
    "kk_kclass_get_instance_size_words",
    "kk_kclass_get_qualified_name",
    "kk_kclass_get_simple_name",
    "kk_kclass_get_superclass_name",
    "kk_kclass_is_data_class",
    "kk_kclass_is_sealed_class",
    "kk_kclass_is_value_class",
].map { bridgeSpec($0, section: "TypeCheck", params: ["kclassRaw"]) }

private let sequenceOnlyBridgeFunctions: [RuntimeABIFunctionSpec] =
    [
        bridgeSpec(
            "kk_sequence_fold",
            section: "Sequence",
            typedParams: [
                ("seqRaw", .intptr),
                ("initial", .intptr),
                ("fnPtr", .intptr),
                ("closureRaw", .intptr),
                ("outThrown", .nullableIntptrPointer),
            ]
        ),
    ]

public extension RuntimeABISpec {
    static let runtimeOnlyBridgeFunctions: [RuntimeABIFunctionSpec] =
        arrayHOFBridgeFunctions
        + arrayFoldBridgeFunctions
        + arraySpecialBridgeFunctions
        + numericOnlyBridgeFunctions
        + coroutineOnlyBridgeFunctions
        + kclassBridgeFunctions
        + sequenceOnlyBridgeFunctions
}
