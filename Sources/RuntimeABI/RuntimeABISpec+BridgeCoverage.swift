func bridgeSpec(
    _ name: String,
    section: String,
    params: [String] = [],
    returnType: RuntimeABICType = .intptr
) -> RuntimeABIFunctionSpec {
    RuntimeABIFunctionSpec(
        name: name,
        parameters: params.map { RuntimeABIParameter(name: $0, type: .intptr) },
        returnType: returnType,
        section: section
    )
}

func bridgeSpec(
    _ name: String,
    section: String,
    typedParams: [(String, RuntimeABICType)],
    returnType: RuntimeABICType = .intptr
) -> RuntimeABIFunctionSpec {
    RuntimeABIFunctionSpec(
        name: name,
        parameters: typedParams.map { RuntimeABIParameter(name: $0.0, type: $0.1) },
        returnType: returnType,
        section: section
    )
}

private let collectionBridgeBase: [RuntimeABIFunctionSpec] = [
    bridgeSpec("kk_indexing_iterable_hasNext", section: "Collection", params: ["iterRaw"]),
    bridgeSpec("kk_indexing_iterable_iterator", section: "Collection", params: ["iterableRaw"]),
    bridgeSpec("kk_indexing_iterable_next", section: "Collection", params: ["iterRaw"]),
    bridgeSpec("kk_iterable_asSequence", section: "Sequence", params: ["iterableRaw"]),
]

private let listClosureBridgeNames = [
    "kk_list_distinctBy",
    "kk_list_filterIndexed",
    "kk_list_filterNot",
    "kk_list_maxOf",
    "kk_list_maxWith",
    "kk_list_maxWithOrNull",
    "kk_list_minOf",
    "kk_list_minWith",
    "kk_list_minWithOrNull",
    "kk_list_onEach",
    "kk_list_onEachIndexed",
    "kk_list_reduceIndexed",
    "kk_list_reduceIndexedOrNull",
    "kk_list_runningReduceIndexed",
    "kk_list_sortedBy_primitive",
    "kk_list_sortedByDescending_primitive",
]

private let listClosureBridgeFunctions = listClosureBridgeNames.map {
    bridgeSpec(
        $0,
        section: "Collection",
        typedParams: [
            ("listRaw", .intptr),
            ("fnPtr", .intptr),
            ("closureRaw", .intptr),
            ("outThrown", .nullableIntptrPointer),
        ]
    )
}

private let listComparatorBridgeFunctions = [
    "kk_list_maxOfWith",
    "kk_list_maxOfWithOrNull",
    "kk_list_minOfWith",
    "kk_list_minOfWithOrNull",
].map {
    bridgeSpec(
        $0,
        section: "Collection",
        typedParams: [
            ("listRaw", .intptr),
            ("cmpFnPtr", .intptr),
            ("cmpClosureRaw", .intptr),
            ("selFnPtr", .intptr),
            ("selClosureRaw", .intptr),
            ("outThrown", .nullableIntptrPointer),
        ]
    )
}

private let listIndexedBridgeFunctions: [RuntimeABIFunctionSpec] = [
    bridgeSpec(
        "kk_list_foldIndexed",
        section: "Collection",
        typedParams: [
            ("listRaw", .intptr),
            ("initial", .intptr),
            ("fnPtr", .intptr),
            ("closureRaw", .intptr),
            ("outThrown", .nullableIntptrPointer),
        ]
    ),
    bridgeSpec(
        "kk_list_runningFoldIndexed",
        section: "Collection",
        typedParams: [
            ("listRaw", .intptr),
            ("initial", .intptr),
            ("fnPtr", .intptr),
            ("closureRaw", .intptr),
            ("outThrown", .nullableIntptrPointer),
        ]
    ),
    bridgeSpec(
        "kk_list_scanIndexed",
        section: "Collection",
        typedParams: [
            ("listRaw", .intptr),
            ("initial", .intptr),
            ("fnPtr", .intptr),
            ("closureRaw", .intptr),
            ("outThrown", .nullableIntptrPointer),
        ]
    ),
]

private let listMiscBridgeFunctions: [RuntimeABIFunctionSpec] = [
    bridgeSpec("kk_list_intersect", section: "Collection", params: ["listRaw", "otherRaw"]),
    bridgeSpec("kk_list_of_not_null", section: "Collection", params: ["arrayRaw", "count"]),
    bridgeSpec("kk_list_singleOrNull", section: "Collection", params: ["listRaw"]),
    bridgeSpec("kk_list_subtract", section: "Collection", params: ["listRaw", "otherRaw"]),
    bridgeSpec("kk_list_toHashSet", section: "Collection", params: ["listRaw"]),
    bridgeSpec("kk_list_union", section: "Collection", params: ["listRaw", "otherRaw"]),
]

private let mapBridgeFunctions = [
    "kk_map_flatMap",
    "kk_map_maxByOrNull",
    "kk_map_minByOrNull",
].map {
    bridgeSpec(
        $0,
        section: "Collection",
        typedParams: [
            ("mapRaw", .intptr),
            ("fnPtr", .intptr),
            ("closureRaw", .intptr),
            ("outThrown", .nullableIntptrPointer),
        ]
    )
}

private let mutableListBridgeFunctions: [RuntimeABIFunctionSpec] =
    [bridgeSpec("kk_mutable_list_sort", section: "Collection", params: ["listRaw"])]
    + [
        "kk_mutable_list_sort_primitive",
        "kk_mutable_list_sortBy",
        "kk_mutable_list_sortBy_primitive",
        "kk_mutable_list_sortByDescending",
        "kk_mutable_list_sortByDescending_primitive",
        "kk_mutable_list_sortDescending_primitive",
    ].map {
        switch $0 {
        case "kk_mutable_list_sort_primitive", "kk_mutable_list_sortDescending_primitive":
            return bridgeSpec(
                $0,
                section: "Collection",
                typedParams: [
                    ("listRaw", .intptr),
                    ("kindRaw", .int32),
                ]
            )
        case "kk_mutable_list_sortBy_primitive", "kk_mutable_list_sortByDescending_primitive":
            return bridgeSpec(
                $0,
                section: "Collection",
                typedParams: [
                    ("listRaw", .intptr),
                    ("fnPtr", .intptr),
                    ("closureRaw", .intptr),
                    ("kindRaw", .int32),
                    ("outThrown", .nullableIntptrPointer),
                ]
            )
        default:
            return bridgeSpec(
                $0,
                section: "Collection",
                typedParams: [
                    ("listRaw", .intptr),
                    ("fnPtr", .intptr),
                    ("closureRaw", .intptr),
                    ("outThrown", .nullableIntptrPointer),
                ]
            )
        }
    }

private let sequenceAndSetBridgeFunctions: [RuntimeABIFunctionSpec] = [
    bridgeSpec("kk_range_hasNext", section: "Range", params: ["iterRaw"]),
    bridgeSpec("kk_range_iterator", section: "Range", params: ["rangeRaw"]),
    bridgeSpec("kk_range_next", section: "Range", params: ["iterRaw"]),
    bridgeSpec("kk_uint_range_hasNext", section: "Range", params: ["iterRaw"]),
    bridgeSpec("kk_uint_range_iterator", section: "Range", params: ["rangeRaw"]),
    bridgeSpec("kk_uint_range_next", section: "Range", params: ["iterRaw"]),
    bridgeSpec("kk_sequence_asIterable", section: "Sequence", params: ["seqRaw"]),
    bridgeSpec("kk_sequence_dropWhile", section: "Sequence", params: ["seqRaw", "fnPtr", "closureRaw"]),
    bridgeSpec("kk_sequence_filterNot", section: "Sequence", params: ["seqRaw", "fnPtr", "closureRaw"]),
    bridgeSpec(
        "kk_sequence_find",
        section: "Sequence",
        typedParams: [
            ("seqRaw", .intptr),
            ("fnPtr", .intptr),
            ("closureRaw", .intptr),
            ("outThrown", .nullableIntptrPointer),
        ]
    ),
    bridgeSpec("kk_sequence_takeWhile", section: "Sequence", params: ["seqRaw", "fnPtr", "closureRaw"]),
    bridgeSpec("kk_set_containsAll", section: "Collection", params: ["setRaw", "collectionRaw"]),
    bridgeSpec("kk_set_sorted", section: "Collection", params: ["setRaw"]),
    bridgeSpec("kk_set_sortedDescending", section: "Collection", params: ["setRaw"]),
]

public extension RuntimeABISpec {
    static let numericRuntimeBridgeFunctions: [RuntimeABIFunctionSpec] =
        [
            "kk_char_category",
            "kk_char_code",
            "kk_char_directionality",
            "kk_char_toDouble",
            "kk_char_toDoubleOrNull",
            "kk_char_toInt",
            "kk_char_toIntOrNull",
        ].map { bridgeSpec($0, section: "Char", params: ["value"]) }
        + [
            bridgeSpec("kk_char_minus", section: "Char", params: ["lhsRaw", "rhsRaw"]),
        ]
        + [
            bridgeSpec("kk_double_fromBits", section: "NumericConversion", params: ["bits"]),
            bridgeSpec("kk_double_isFinite", section: "NumericConversion", params: ["value"]),
            bridgeSpec("kk_double_isInfinite", section: "NumericConversion", params: ["value"]),
            bridgeSpec("kk_double_isNaN", section: "NumericConversion", params: ["value"]),
            bridgeSpec("kk_double_toBits", section: "NumericConversion", params: ["value"]),
            bridgeSpec("kk_double_toRawBits", section: "NumericConversion", params: ["value"]),
            bridgeSpec("kk_double_to_char", section: "NumericConversion", params: ["value"]),
            bridgeSpec("kk_double_to_uint", section: "NumericConversion", params: ["value"]),
            bridgeSpec("kk_double_to_ulong", section: "NumericConversion", params: ["value"]),
            bridgeSpec("kk_float_fromBits", section: "NumericConversion", params: ["bits"]),
            bridgeSpec("kk_float_isFinite", section: "NumericConversion", params: ["value"]),
            bridgeSpec("kk_float_isInfinite", section: "NumericConversion", params: ["value"]),
            bridgeSpec("kk_float_isNaN", section: "NumericConversion", params: ["value"]),
            bridgeSpec("kk_float_toBits", section: "NumericConversion", params: ["value"]),
            bridgeSpec("kk_float_toRawBits", section: "NumericConversion", params: ["value"]),
            bridgeSpec("kk_float_to_char", section: "NumericConversion", params: ["value"]),
            bridgeSpec("kk_float_to_double_bits", section: "NumericConversion", params: ["value"]),
            bridgeSpec("kk_float_to_uint", section: "NumericConversion", params: ["value"]),
            bridgeSpec("kk_float_to_ulong", section: "NumericConversion", params: ["value"]),
            bridgeSpec("kk_int_to_double_bits", section: "NumericConversion", params: ["value"]),
            bridgeSpec("kk_int_to_float_bits", section: "NumericConversion", params: ["value"]),
            bridgeSpec("kk_int_to_long", section: "NumericConversion", params: ["value"]),
            bridgeSpec("kk_int_to_uint", section: "NumericConversion", params: ["value"]),
            bridgeSpec("kk_int_to_ulong", section: "NumericConversion", params: ["value"]),
            bridgeSpec("kk_long_to_uint", section: "NumericConversion", params: ["value"]),
            bridgeSpec("kk_long_to_ulong", section: "NumericConversion", params: ["value"]),
            bridgeSpec("kk_uint_to_int", section: "NumericConversion", params: ["value"]),
            bridgeSpec("kk_uint_to_long", section: "NumericConversion", params: ["value"]),
            bridgeSpec("kk_uint_to_ulong", section: "NumericConversion", params: ["value"]),
            bridgeSpec("kk_ulong_to_int", section: "NumericConversion", params: ["value"]),
        ]
        + [
            "kk_op_dadd",
            "kk_op_ddiv",
            "kk_op_deq",
            "kk_op_dge",
            "kk_op_dgt",
            "kk_op_dle",
            "kk_op_dlt",
            "kk_op_dmod",
            "kk_op_dne",
            "kk_op_dsub",
            "kk_op_elvis",
            "kk_op_fadd",
            "kk_op_fdiv",
            "kk_op_feq",
            "kk_op_fge",
            "kk_op_fgt",
            "kk_op_fle",
            "kk_op_flt",
            "kk_op_fmod",
            "kk_op_fmul",
            "kk_op_fne",
            "kk_op_fsub",
            "kk_structural_ne",
        ].map { bridgeSpec($0, section: "Operator", params: ["lhs", "rhs"]) }
        + [
            bridgeSpec(
                "kk_op_notnull",
                section: "Operator",
                typedParams: [
                    ("value", .intptr),
                    ("outThrown", .nullableIntptrPointer),
                ]
            ),
            bridgeSpec("kk_println_char", section: "ConsolePrint", params: ["value"], returnType: .void),
            bridgeSpec("kk_println_double", section: "ConsolePrint", params: ["value"], returnType: .void),
            bridgeSpec("kk_println_float", section: "ConsolePrint", params: ["value"], returnType: .void),
            bridgeSpec("kk_println_long", section: "ConsolePrint", params: ["value"], returnType: .void),
            bridgeSpec("kk_ulong_range_contains", section: "Range", params: ["rangeRaw", "value"]),
            bridgeSpec("kk_ulong_range_first", section: "Range", params: ["rangeRaw"]),
            bridgeSpec("kk_ulong_range_isEmpty", section: "Range", params: ["rangeRaw"]),
            bridgeSpec("kk_ulong_range_last", section: "Range", params: ["rangeRaw"]),
            bridgeSpec("kk_ulong_range_step", section: "Range", params: ["rangeRaw"]),
            bridgeSpec("kk_ulong_range_toULongArray", section: "Range", params: ["rangeRaw"]),
        ]

    static let collectionBridgeFunctions: [RuntimeABIFunctionSpec] =
        collectionBridgeBase
        + listClosureBridgeFunctions
        + listComparatorBridgeFunctions
        + listIndexedBridgeFunctions
        + listMiscBridgeFunctions
        + mapBridgeFunctions
        + mutableListBridgeFunctions
        + sequenceAndSetBridgeFunctions

    static let timeAndPathBridgeFunctions: [RuntimeABIFunctionSpec] =
        [
            bridgeSpec("kk_duration_div_int", section: "Duration", params: ["durationRaw", "scale"]),
            bridgeSpec("kk_duration_isFinite", section: "Duration", params: ["durationRaw"]),
            bridgeSpec("kk_duration_isInfinite", section: "Duration", params: ["durationRaw"]),
            bridgeSpec("kk_duration_isNegative", section: "Duration", params: ["durationRaw"]),
            bridgeSpec("kk_duration_isPositive", section: "Duration", params: ["durationRaw"]),
            bridgeSpec("kk_duration_to_java_duration", section: "Duration", params: ["durationRaw"]),
            bridgeSpec("kk_duration_times_int", section: "Duration", params: ["durationRaw", "scale"]),
            bridgeSpec("kk_duration_unary_minus", section: "Duration", params: ["durationRaw"]),
            bridgeSpec("kk_java_duration_to_kotlin_duration", section: "Duration", params: ["durationRaw"]),
            bridgeSpec("kk_instant_compare", section: "System", params: ["aRaw", "bRaw"]),
            bridgeSpec("kk_instant_epoch_seconds", section: "System", params: ["instantRaw"]),
            bridgeSpec("kk_instant_from_epoch_millis", section: "System", params: ["millis"]),
            bridgeSpec("kk_instant_elapsed", section: "System", params: ["instantRaw"]),
            bridgeSpec("kk_instant_minus_duration", section: "System", params: ["instantRaw", "durationRaw"]),
            bridgeSpec("kk_instant_nano_of_second", section: "System", params: ["instantRaw"]),
            bridgeSpec("kk_instant_now", section: "System"),
            bridgeSpec("kk_instant_plus_duration", section: "System", params: ["instantRaw", "durationRaw"]),
            bridgeSpec("kk_instant_to_java_instant", section: "System", params: ["instantRaw"]),
            bridgeSpec("kk_instant_to_js_date", section: "System", params: ["instantRaw"]),
            bridgeSpec("kk_instant_until", section: "System", params: ["fromRaw", "toRaw"]),
            bridgeSpec("kk_java_instant_to_kotlin_instant", section: "System", params: ["instantRaw"]),
            bridgeSpec("kk_js_date_to_kotlin_instant", section: "System", params: ["dateRaw"]),
            // STDLIB-TIME-181: java.time.Instant accessors
            bridgeSpec("kk_java_instant_epoch_seconds", section: "System", params: ["instantRaw"]),
            bridgeSpec("kk_java_instant_nano_of_second", section: "System", params: ["instantRaw"]),
            bridgeSpec("kk_java_instant_to_epoch_milli", section: "System", params: ["instantRaw"]),
            bridgeSpec("kk_java_instant_of_epoch_second", section: "System", params: ["epochSeconds", "nanoOfSecond"]),
            bridgeSpec("kk_java_instant_of_epoch_milli", section: "System", params: ["epochMillis"]),
            bridgeSpec("kk_java_instant_to_string", section: "System", params: ["instantRaw"]),
            // STDLIB-TIME-181: java.time.Duration accessors
            bridgeSpec("kk_java_duration_seconds", section: "Duration", params: ["durationRaw"]),
            bridgeSpec("kk_java_duration_nano", section: "Duration", params: ["durationRaw"]),
            bridgeSpec("kk_java_duration_to_millis", section: "Duration", params: ["durationRaw"]),
            bridgeSpec("kk_java_duration_of_seconds", section: "Duration", params: ["seconds", "nanoAdjustment"]),
            bridgeSpec("kk_java_duration_of_millis", section: "Duration", params: ["millis"]),
            bridgeSpec("kk_java_duration_to_string", section: "Duration", params: ["durationRaw"]),
            // STDLIB-TIME-181: JS Date accessors
            bridgeSpec("kk_js_date_epoch_millis", section: "System", params: ["dateRaw"]),
            bridgeSpec("kk_js_date_from_epoch_millis", section: "System", params: ["epochMillis"]),
            bridgeSpec("kk_js_date_to_string", section: "System", params: ["dateRaw"]),
            // STDLIB-TIME-181: Native Foundation Date bridge
            bridgeSpec("kk_instant_to_foundation_date", section: "System", params: ["instantRaw"]),
            bridgeSpec("kk_foundation_date_to_kotlin_instant", section: "System", params: ["dateRaw"]),
            // STDLIB-TIME-181: Native clock_gettime bridge
            bridgeSpec("kk_clock_gettime_realtime", section: "System"),
            bridgeSpec("kk_clock_gettime_monotonic_ns", section: "System"),
            bridgeSpec("kk_clock_monotonic_mark_now", section: "System"),
            // STDLIB-TIME-181: Type-safe epoch conversion helpers
            bridgeSpec("kk_instant_to_epoch_millis", section: "System", params: ["instantRaw"]),
            bridgeSpec("kk_instant_from_epoch_seconds", section: "System", params: ["epochSeconds", "nanoOfSecond"]),
            bridgeSpec("kk_platform_canAccessUnaligned", section: "System", params: ["platformRaw"]),
            bridgeSpec("kk_platform_isLittleEndian", section: "System", params: ["platformRaw"]),
            bridgeSpec("kk_platform_osFamily", section: "System", params: ["platformRaw"]),
            bridgeSpec("kk_platform_cpuArchitecture", section: "System", params: ["platformRaw"]),
            bridgeSpec("kk_platform_getAvailableProcessors", section: "System", params: ["platformRaw"]),
            bridgeSpec("kk_platform_memoryModel", section: "System", params: ["platformRaw"]),
            bridgeSpec("kk_platform_isDebugBinary", section: "System", params: ["platformRaw"]),
            bridgeSpec("kk_time_source_mark_now", section: "Duration", params: ["receiver"]),
            bridgeSpec("kk_time_source_monotonic_mark_now", section: "Duration", params: ["receiver"]),
            bridgeSpec("kk_time_mark_elapsed_now", section: "Duration", params: ["markRaw"]),
            bridgeSpec("kk_time_mark_has_passed_now", section: "Duration", params: ["markRaw"]),
            bridgeSpec("kk_time_mark_has_not_passed_now", section: "Duration", params: ["markRaw"]),
            bridgeSpec("kk_time_mark_plus_duration", section: "Duration", params: ["markRaw", "durationRaw"]),
            bridgeSpec("kk_time_mark_minus_duration", section: "Duration", params: ["markRaw", "durationRaw"]),
            bridgeSpec("kk_time_mark_minus_mark", section: "Duration", params: ["lhsRaw", "rhsRaw"]),
            bridgeSpec("kk_time_mark_compare", section: "Duration", params: ["lhsRaw", "rhsRaw"]),
            bridgeSpec("kk_clock_now", section: "System", params: ["receiver"]),
            bridgeSpec("kk_clock_system_now", section: "System"),
            bridgeSpec("kk_path_deleteIfExists", section: "FileIO", params: ["pathRaw"]),
            bridgeSpec("kk_path_exists", section: "FileIO", params: ["pathRaw"]),
            bridgeSpec("kk_path_isDirectory", section: "FileIO", params: ["pathRaw"]),
            bridgeSpec("kk_path_isRegularFile", section: "FileIO", params: ["pathRaw"]),
            bridgeSpec("kk_path_name", section: "FileIO", params: ["pathRaw"]),
            bridgeSpec("kk_path_new", section: "FileIO", params: ["pathStringRaw"]),
            bridgeSpec("kk_path_parent", section: "FileIO", params: ["pathRaw"]),
            bridgeSpec("kk_path_resolve_path", section: "FileIO", params: ["pathRaw", "otherRaw"]),
            bridgeSpec("kk_path_resolve_string", section: "FileIO", params: ["pathRaw", "otherRaw"]),
            bridgeSpec("kk_path_toString", section: "FileIO", params: ["pathRaw"]),
            bridgeSpec("kk_result_component1", section: "Result", params: ["resultRaw"]),
            bridgeSpec("kk_result_component2", section: "Result", params: ["resultRaw"]),
            bridgeSpec("kk_with_timeout", section: "Coroutine", params: ["timeoutMillis", "entryPointRaw", "continuation"]),
            bridgeSpec("kk_with_timeout_or_null", section: "Coroutine", params: ["timeoutMillis", "entryPointRaw", "continuation"]),
        ]
        + [
            "kk_path_createDirectories",
            "kk_path_listDirectoryEntries",
            "kk_path_readLines",
            "kk_path_readText",
        ].map {
            bridgeSpec(
                $0,
                section: "FileIO",
                typedParams: [
                    ("pathRaw", .intptr),
                    ("outThrown", .nullableIntptrPointer),
                ]
            )
        }
        + [
            bridgeSpec(
                "kk_path_writeText",
                section: "FileIO",
                typedParams: [
                    ("pathRaw", .intptr),
                    ("textRaw", .intptr),
                    ("outThrown", .nullableIntptrPointer),
                ]
            ),
            bridgeSpec(
                "kk_result_recoverCatching",
                section: "Result",
                typedParams: [
                    ("resultRaw", .intptr),
                    ("fnPtr", .intptr),
                    ("closureRaw", .intptr),
                    ("outThrown", .nullableIntptrPointer),
                ]
            ),
        ]

    static let dispatchBridgeFunctions: [RuntimeABIFunctionSpec] = [
        bridgeSpec("kk_itable_lookup", section: "Delegate", params: ["receiver", "ifaceSlot", "methodSlot"]),
        bridgeSpec("kk_vtable_lookup", section: "Delegate", params: ["receiver", "slot"]),
    ]

    static let stringBridgeFunctions: [RuntimeABIFunctionSpec] = [
        bridgeSpec("kk_string_singleOrNull", section: "String", params: ["strRaw"]),
        bridgeSpec("kk_string_substringAfter", section: "String", params: ["strRaw", "delimiterRaw"]),
    ]
}
