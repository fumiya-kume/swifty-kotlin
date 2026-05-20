// swiftlint:disable file_length

/// `RuntimeABISpec.rangeFunctions` (P5-68) extracted from `RuntimeABISpec.swift`.
public extension RuntimeABISpec {
    /// Range/Progression (P5-68)
    public static let rangeFunctions: [RuntimeABIFunctionSpec] = [
        RuntimeABIFunctionSpec(
            name: "kk_op_rangeTo",
            parameters: [
                RuntimeABIParameter(name: "a", type: .intptr),
                RuntimeABIParameter(name: "b", type: .intptr),
            ],
            returnType: .intptr,
            section: "Range"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_op_rangeUntil",
            parameters: [
                RuntimeABIParameter(name: "a", type: .intptr),
                RuntimeABIParameter(name: "b", type: .intptr),
            ],
            returnType: .intptr,
            section: "Range"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_op_ulong_rangeUntil",
            parameters: [
                RuntimeABIParameter(name: "a", type: .intptr),
                RuntimeABIParameter(name: "b", type: .intptr),
            ],
            returnType: .intptr,
            section: "Range"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_op_downTo",
            parameters: [
                RuntimeABIParameter(name: "a", type: .intptr),
                RuntimeABIParameter(name: "b", type: .intptr),
            ],
            returnType: .intptr,
            section: "Range"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_op_step",
            parameters: [
                RuntimeABIParameter(name: "rangeRaw", type: .intptr),
                RuntimeABIParameter(name: "stepVal", type: .intptr),
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "Range"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_range_first",
            parameters: [
                RuntimeABIParameter(name: "rangeRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "Range"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_range_start",
            parameters: [
                RuntimeABIParameter(name: "rangeRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "Range"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_range_last",
            parameters: [
                RuntimeABIParameter(name: "rangeRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "Range"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_long_range_firstOrNull",
            parameters: [
                RuntimeABIParameter(name: "rangeRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "Range"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_long_range_lastOrNull",
            parameters: [
                RuntimeABIParameter(name: "rangeRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "Range"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_range_endExclusive",
            parameters: [
                RuntimeABIParameter(name: "rangeRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "Range"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_range_count",
            parameters: [
                RuntimeABIParameter(name: "rangeRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "Range"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_range_isEmpty",
            parameters: [
                RuntimeABIParameter(name: "rangeRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "Range"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_range_sum",
            parameters: [
                RuntimeABIParameter(name: "rangeRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "Range"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_range_toList",
            parameters: [
                RuntimeABIParameter(name: "rangeRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "Range"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_ulong_range_toList",
            parameters: [
                RuntimeABIParameter(name: "rangeRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "Range"
        ),
        // ULongRange count, iterator, forEach, map (STDLIB-RANGE-037)
        RuntimeABIFunctionSpec(
            name: "kk_ulong_range_count",
            parameters: [
                RuntimeABIParameter(name: "rangeRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "Range"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_ulong_range_iterator",
            parameters: [
                RuntimeABIParameter(name: "rangeRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "Range"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_ulong_range_hasNext",
            parameters: [
                RuntimeABIParameter(name: "iterRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "Range"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_ulong_range_next",
            parameters: [
                RuntimeABIParameter(name: "iterRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "Range"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_ulong_range_forEach",
            parameters: [
                RuntimeABIParameter(name: "rangeRaw", type: .intptr),
                RuntimeABIParameter(name: "lambdaRaw", type: .intptr),
                RuntimeABIParameter(name: "captureRaw", type: .intptr),
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "Range"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_ulong_range_map",
            parameters: [
                RuntimeABIParameter(name: "rangeRaw", type: .intptr),
                RuntimeABIParameter(name: "lambdaRaw", type: .intptr),
                RuntimeABIParameter(name: "captureRaw", type: .intptr),
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "Range"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_range_forEach",
            parameters: [
                RuntimeABIParameter(name: "rangeRaw", type: .intptr),
                RuntimeABIParameter(name: "lambdaRaw", type: .intptr),
                RuntimeABIParameter(name: "captureRaw", type: .intptr),
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "Range"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_range_map",
            parameters: [
                RuntimeABIParameter(name: "rangeRaw", type: .intptr),
                RuntimeABIParameter(name: "lambdaRaw", type: .intptr),
                RuntimeABIParameter(name: "captureRaw", type: .intptr),
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "Range"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_range_step",
            parameters: [
                RuntimeABIParameter(name: "rangeRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "Range"
        ),
        // Range HOFs (STDLIB-RANGE-038)
        RuntimeABIFunctionSpec(
            name: "kk_range_mapIndexed",
            parameters: [
                RuntimeABIParameter(name: "rangeRaw", type: .intptr),
                RuntimeABIParameter(name: "lambdaRaw", type: .intptr),
                RuntimeABIParameter(name: "captureRaw", type: .intptr),
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "Range"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_range_mapNotNull",
            parameters: [
                RuntimeABIParameter(name: "rangeRaw", type: .intptr),
                RuntimeABIParameter(name: "lambdaRaw", type: .intptr),
                RuntimeABIParameter(name: "captureRaw", type: .intptr),
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "Range"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_range_filter",
            parameters: [
                RuntimeABIParameter(name: "rangeRaw", type: .intptr),
                RuntimeABIParameter(name: "lambdaRaw", type: .intptr),
                RuntimeABIParameter(name: "captureRaw", type: .intptr),
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "Range"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_range_filterIndexed",
            parameters: [
                RuntimeABIParameter(name: "rangeRaw", type: .intptr),
                RuntimeABIParameter(name: "lambdaRaw", type: .intptr),
                RuntimeABIParameter(name: "captureRaw", type: .intptr),
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "Range"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_range_filterNot",
            parameters: [
                RuntimeABIParameter(name: "rangeRaw", type: .intptr),
                RuntimeABIParameter(name: "lambdaRaw", type: .intptr),
                RuntimeABIParameter(name: "captureRaw", type: .intptr),
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "Range"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_range_reduce",
            parameters: [
                RuntimeABIParameter(name: "rangeRaw", type: .intptr),
                RuntimeABIParameter(name: "lambdaRaw", type: .intptr),
                RuntimeABIParameter(name: "captureRaw", type: .intptr),
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "Range"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_range_reduceIndexed",
            parameters: [
                RuntimeABIParameter(name: "rangeRaw", type: .intptr),
                RuntimeABIParameter(name: "lambdaRaw", type: .intptr),
                RuntimeABIParameter(name: "captureRaw", type: .intptr),
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "Range"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_range_fold",
            parameters: [
                RuntimeABIParameter(name: "rangeRaw", type: .intptr),
                RuntimeABIParameter(name: "initialValue", type: .intptr),
                RuntimeABIParameter(name: "lambdaRaw", type: .intptr),
                RuntimeABIParameter(name: "captureRaw", type: .intptr),
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "Range"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_range_foldIndexed",
            parameters: [
                RuntimeABIParameter(name: "rangeRaw", type: .intptr),
                RuntimeABIParameter(name: "initialValue", type: .intptr),
                RuntimeABIParameter(name: "lambdaRaw", type: .intptr),
                RuntimeABIParameter(name: "captureRaw", type: .intptr),
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "Range"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_range_find",
            parameters: [
                RuntimeABIParameter(name: "rangeRaw", type: .intptr),
                RuntimeABIParameter(name: "lambdaRaw", type: .intptr),
                RuntimeABIParameter(name: "captureRaw", type: .intptr),
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "Range"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_range_findLast",
            parameters: [
                RuntimeABIParameter(name: "rangeRaw", type: .intptr),
                RuntimeABIParameter(name: "lambdaRaw", type: .intptr),
                RuntimeABIParameter(name: "captureRaw", type: .intptr),
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "Range"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_range_first_predicate",
            parameters: [
                RuntimeABIParameter(name: "rangeRaw", type: .intptr),
                RuntimeABIParameter(name: "lambdaRaw", type: .intptr),
                RuntimeABIParameter(name: "captureRaw", type: .intptr),
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "Range"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_range_firstOrNull_predicate",
            parameters: [
                RuntimeABIParameter(name: "rangeRaw", type: .intptr),
                RuntimeABIParameter(name: "lambdaRaw", type: .intptr),
                RuntimeABIParameter(name: "captureRaw", type: .intptr),
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "Range"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_range_last_predicate",
            parameters: [
                RuntimeABIParameter(name: "rangeRaw", type: .intptr),
                RuntimeABIParameter(name: "lambdaRaw", type: .intptr),
                RuntimeABIParameter(name: "captureRaw", type: .intptr),
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "Range"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_range_lastOrNull_predicate",
            parameters: [
                RuntimeABIParameter(name: "rangeRaw", type: .intptr),
                RuntimeABIParameter(name: "lambdaRaw", type: .intptr),
                RuntimeABIParameter(name: "captureRaw", type: .intptr),
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "Range"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_range_any",
            parameters: [
                RuntimeABIParameter(name: "rangeRaw", type: .intptr),
                RuntimeABIParameter(name: "lambdaRaw", type: .intptr),
                RuntimeABIParameter(name: "captureRaw", type: .intptr),
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "Range"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_range_all",
            parameters: [
                RuntimeABIParameter(name: "rangeRaw", type: .intptr),
                RuntimeABIParameter(name: "lambdaRaw", type: .intptr),
                RuntimeABIParameter(name: "captureRaw", type: .intptr),
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "Range"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_range_none",
            parameters: [
                RuntimeABIParameter(name: "rangeRaw", type: .intptr),
                RuntimeABIParameter(name: "lambdaRaw", type: .intptr),
                RuntimeABIParameter(name: "captureRaw", type: .intptr),
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "Range"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_range_chunked",
            parameters: [
                RuntimeABIParameter(name: "rangeRaw", type: .intptr),
                RuntimeABIParameter(name: "size", type: .intptr),
            ],
            returnType: .intptr,
            section: "Range"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_range_windowed",
            parameters: [
                RuntimeABIParameter(name: "rangeRaw", type: .intptr),
                RuntimeABIParameter(name: "size", type: .intptr),
                RuntimeABIParameter(name: "step", type: .intptr),
                RuntimeABIParameter(name: "partialWindows", type: .intptr),
            ],
            returnType: .intptr,
            section: "Range"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_range_reversed",
            parameters: [
                RuntimeABIParameter(name: "rangeRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "Range"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_range_toIntArray",
            parameters: [
                RuntimeABIParameter(name: "rangeRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "Range"
        ),
        // Progression fromClosedRange (STDLIB-RANGE-039)
        RuntimeABIFunctionSpec(
            name: "kk_int_progression_fromClosedRange",
            parameters: [
                RuntimeABIParameter(name: "receiverRaw", type: .intptr),
                RuntimeABIParameter(name: "rangeStart", type: .intptr),
                RuntimeABIParameter(name: "rangeEnd", type: .intptr),
                RuntimeABIParameter(name: "step", type: .intptr),
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "Range"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_long_progression_fromClosedRange",
            parameters: [
                RuntimeABIParameter(name: "receiverRaw", type: .intptr),
                RuntimeABIParameter(name: "rangeStart", type: .intptr),
                RuntimeABIParameter(name: "rangeEnd", type: .intptr),
                RuntimeABIParameter(name: "step", type: .intptr),
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "Range"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_uint_progression_fromClosedRange",
            parameters: [
                RuntimeABIParameter(name: "receiverRaw", type: .intptr),
                RuntimeABIParameter(name: "rangeStart", type: .intptr),
                RuntimeABIParameter(name: "rangeEnd", type: .intptr),
                RuntimeABIParameter(name: "step", type: .intptr),
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "Range"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_ulong_progression_fromClosedRange",
            parameters: [
                RuntimeABIParameter(name: "receiverRaw", type: .intptr),
                RuntimeABIParameter(name: "rangeStart", type: .intptr),
                RuntimeABIParameter(name: "rangeEnd", type: .intptr),
                RuntimeABIParameter(name: "step", type: .intptr),
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "Range"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_char_progression_fromClosedRange",
            parameters: [
                RuntimeABIParameter(name: "receiverRaw", type: .intptr),
                RuntimeABIParameter(name: "rangeStart", type: .intptr),
                RuntimeABIParameter(name: "rangeEnd", type: .intptr),
                RuntimeABIParameter(name: "step", type: .intptr),
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "Range"
        ),
        // LongRange (STDLIB-RANGE-035)
        RuntimeABIFunctionSpec(
            name: "kk_long_rangeTo",
            parameters: [
                RuntimeABIParameter(name: "lhs", type: .intptr),
                RuntimeABIParameter(name: "rhs", type: .intptr),
            ],
            returnType: .intptr,
            section: "Range"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_long_range_first",
            parameters: [
                RuntimeABIParameter(name: "rangeRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "Range"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_long_range_last",
            parameters: [
                RuntimeABIParameter(name: "rangeRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "Range"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_long_range_step",
            parameters: [
                RuntimeABIParameter(name: "rangeRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "Range"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_long_range_contains",
            parameters: [
                RuntimeABIParameter(name: "rangeRaw", type: .intptr),
                RuntimeABIParameter(name: "value", type: .intptr),
            ],
            returnType: .intptr,
            section: "Range"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_long_range_isEmpty",
            parameters: [
                RuntimeABIParameter(name: "rangeRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "Range"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_long_range_iterator",
            parameters: [
                RuntimeABIParameter(name: "rangeRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "Range"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_long_range_reversed",
            parameters: [
                RuntimeABIParameter(name: "rangeRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "Range"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_long_range_toList",
            parameters: [
                RuntimeABIParameter(name: "rangeRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "Range"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_long_range_toLongArray",
            parameters: [
                RuntimeABIParameter(name: "rangeRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "Range"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_long_range_count",
            parameters: [
                RuntimeABIParameter(name: "rangeRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "Range"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_long_range_randomOrNull",
            parameters: [
                RuntimeABIParameter(name: "rangeRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "Range"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_long_range_randomOrNull_random",
            parameters: [
                RuntimeABIParameter(name: "rangeRaw", type: .intptr),
                RuntimeABIParameter(name: "randomRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "Range"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_long_range_forEach",
            parameters: [
                RuntimeABIParameter(name: "rangeRaw", type: .intptr),
                RuntimeABIParameter(name: "fnPtr", type: .intptr),
                RuntimeABIParameter(name: "closureRaw", type: .intptr),
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "Range"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_long_range_map",
            parameters: [
                RuntimeABIParameter(name: "rangeRaw", type: .intptr),
                RuntimeABIParameter(name: "fnPtr", type: .intptr),
                RuntimeABIParameter(name: "closureRaw", type: .intptr),
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "Range"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_long_range_random",
            parameters: [
                RuntimeABIParameter(name: "rangeRaw", type: .intptr),
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "Range"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_long_range_random_random",
            parameters: [
                RuntimeABIParameter(name: "rangeRaw", type: .intptr),
                RuntimeABIParameter(name: "randomRaw", type: .intptr),
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "Range"
        ),
        // UIntProgression operations (STDLIB-RANGE-039)
        RuntimeABIFunctionSpec(
            name: "kk_uint_rangeTo",
            parameters: [
                RuntimeABIParameter(name: "lhs", type: .intptr),
                RuntimeABIParameter(name: "rhs", type: .intptr),
            ],
            returnType: .intptr,
            section: "Range"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_uint_downTo",
            parameters: [
                RuntimeABIParameter(name: "lhs", type: .intptr),
                RuntimeABIParameter(name: "rhs", type: .intptr),
            ],
            returnType: .intptr,
            section: "Range"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_uint_step",
            parameters: [
                RuntimeABIParameter(name: "rangeRaw", type: .intptr),
                RuntimeABIParameter(name: "stepValue", type: .intptr),
            ],
            returnType: .intptr,
            section: "Range"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_uint_range_reversed",
            parameters: [
                RuntimeABIParameter(name: "rangeRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "Range"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_uint_range_toList",
            parameters: [
                RuntimeABIParameter(name: "rangeRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "Range"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_uint_range_iterator",
            parameters: [
                RuntimeABIParameter(name: "rangeRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "Range"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_uint_range_hasNext",
            parameters: [
                RuntimeABIParameter(name: "iterRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "Range"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_uint_range_next",
            parameters: [
                RuntimeABIParameter(name: "iterRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "Range"
        ),
        // ULongProgression operations (STDLIB-RANGE-039)
        RuntimeABIFunctionSpec(
            name: "kk_ulong_rangeTo",
            parameters: [
                RuntimeABIParameter(name: "lhs", type: .intptr),
                RuntimeABIParameter(name: "rhs", type: .intptr),
            ],
            returnType: .intptr,
            section: "Range"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_ulong_downTo",
            parameters: [
                RuntimeABIParameter(name: "lhs", type: .intptr),
                RuntimeABIParameter(name: "rhs", type: .intptr),
            ],
            returnType: .intptr,
            section: "Range"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_ulong_step",
            parameters: [
                RuntimeABIParameter(name: "rangeRaw", type: .intptr),
                RuntimeABIParameter(name: "stepValue", type: .intptr),
            ],
            returnType: .intptr,
            section: "Range"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_ulong_range_reversed",
            parameters: [
                RuntimeABIParameter(name: "rangeRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "Range"
        ),
        // CharRange (STDLIB-290)
        RuntimeABIFunctionSpec(
            name: "kk_char_range_isEmpty",
            parameters: [
                RuntimeABIParameter(name: "rangeRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "Range"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_char_range_step",
            parameters: [
                RuntimeABIParameter(name: "rangeRaw", type: .intptr),
                RuntimeABIParameter(name: "stepVal", type: .intptr),
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "Range"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_char_range_toList",
            parameters: [
                RuntimeABIParameter(name: "rangeRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "Range"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_char_range_forEach",
            parameters: [
                RuntimeABIParameter(name: "rangeRaw", type: .intptr),
                RuntimeABIParameter(name: "lambdaRaw", type: .intptr),
                RuntimeABIParameter(name: "captureRaw", type: .intptr),
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "Range"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_char_range_take",
            parameters: [
                RuntimeABIParameter(name: "rangeRaw", type: .intptr),
                RuntimeABIParameter(name: "n", type: .intptr),
            ],
            returnType: .intptr,
            section: "Range"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_char_range_drop",
            parameters: [
                RuntimeABIParameter(name: "rangeRaw", type: .intptr),
                RuntimeABIParameter(name: "n", type: .intptr),
            ],
            returnType: .intptr,
            section: "Range"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_char_range_sorted",
            parameters: [
                RuntimeABIParameter(name: "rangeRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "Range"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_char_range_randomOrNull",
            parameters: [
                RuntimeABIParameter(name: "rangeRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "Range"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_char_range_randomOrNull_random",
            parameters: [
                RuntimeABIParameter(name: "rangeRaw", type: .intptr),
                RuntimeABIParameter(name: "randomRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "Range"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_char_range_random_random",
            parameters: [
                RuntimeABIParameter(name: "rangeRaw", type: .intptr),
                RuntimeABIParameter(name: "randomRaw", type: .intptr),
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "Range"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_range_firstOrNull",
            parameters: [
                RuntimeABIParameter(name: "rangeRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "Range"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_range_lastOrNull",
            parameters: [
                RuntimeABIParameter(name: "rangeRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "Range"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_range_randomOrNull",
            parameters: [
                RuntimeABIParameter(name: "rangeRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "Range"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_range_randomOrNull_random",
            parameters: [
                RuntimeABIParameter(name: "rangeRaw", type: .intptr),
                RuntimeABIParameter(name: "randomRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "Range"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_range_random",
            parameters: [
                RuntimeABIParameter(name: "rangeRaw", type: .intptr),
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "Range"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_range_random_random",
            parameters: [
                RuntimeABIParameter(name: "rangeRaw", type: .intptr),
                RuntimeABIParameter(name: "randomRaw", type: .intptr),
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "Range"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_uint_range_contains",
            parameters: [
                RuntimeABIParameter(name: "rangeRaw", type: .intptr),
                RuntimeABIParameter(name: "value", type: .intptr),
            ],
            returnType: .intptr,
            section: "Range"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_uint_range_first",
            parameters: [
                RuntimeABIParameter(name: "rangeRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "Range"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_uint_range_last",
            parameters: [
                RuntimeABIParameter(name: "rangeRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "Range"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_uint_range_step",
            parameters: [
                RuntimeABIParameter(name: "rangeRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "Range"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_uint_range_isEmpty",
            parameters: [
                RuntimeABIParameter(name: "rangeRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "Range"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_uint_range_count",
            parameters: [
                RuntimeABIParameter(name: "rangeRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "Range"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_uint_range_sum",
            parameters: [
                RuntimeABIParameter(name: "rangeRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "Range"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_uint_range_toUIntArray",
            parameters: [
                RuntimeABIParameter(name: "rangeRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "Range"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_uint_range_forEach",
            parameters: [
                RuntimeABIParameter(name: "rangeRaw", type: .intptr),
                RuntimeABIParameter(name: "lambdaRaw", type: .intptr),
                RuntimeABIParameter(name: "captureRaw", type: .intptr),
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "Range"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_uint_range_map",
            parameters: [
                RuntimeABIParameter(name: "rangeRaw", type: .intptr),
                RuntimeABIParameter(name: "lambdaRaw", type: .intptr),
                RuntimeABIParameter(name: "captureRaw", type: .intptr),
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "Range"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_uint_range_mapIndexed",
            parameters: [
                RuntimeABIParameter(name: "rangeRaw", type: .intptr),
                RuntimeABIParameter(name: "lambdaRaw", type: .intptr),
                RuntimeABIParameter(name: "captureRaw", type: .intptr),
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "Range"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_uint_range_mapNotNull",
            parameters: [
                RuntimeABIParameter(name: "rangeRaw", type: .intptr),
                RuntimeABIParameter(name: "lambdaRaw", type: .intptr),
                RuntimeABIParameter(name: "captureRaw", type: .intptr),
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "Range"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_uint_range_filter",
            parameters: [
                RuntimeABIParameter(name: "rangeRaw", type: .intptr),
                RuntimeABIParameter(name: "lambdaRaw", type: .intptr),
                RuntimeABIParameter(name: "captureRaw", type: .intptr),
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "Range"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_uint_range_filterIndexed",
            parameters: [
                RuntimeABIParameter(name: "rangeRaw", type: .intptr),
                RuntimeABIParameter(name: "lambdaRaw", type: .intptr),
                RuntimeABIParameter(name: "captureRaw", type: .intptr),
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "Range"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_uint_range_filterNot",
            parameters: [
                RuntimeABIParameter(name: "rangeRaw", type: .intptr),
                RuntimeABIParameter(name: "lambdaRaw", type: .intptr),
                RuntimeABIParameter(name: "captureRaw", type: .intptr),
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "Range"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_uint_range_reduce",
            parameters: [
                RuntimeABIParameter(name: "rangeRaw", type: .intptr),
                RuntimeABIParameter(name: "lambdaRaw", type: .intptr),
                RuntimeABIParameter(name: "captureRaw", type: .intptr),
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "Range"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_uint_range_reduceIndexed",
            parameters: [
                RuntimeABIParameter(name: "rangeRaw", type: .intptr),
                RuntimeABIParameter(name: "lambdaRaw", type: .intptr),
                RuntimeABIParameter(name: "captureRaw", type: .intptr),
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "Range"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_uint_range_fold",
            parameters: [
                RuntimeABIParameter(name: "rangeRaw", type: .intptr),
                RuntimeABIParameter(name: "initialValue", type: .intptr),
                RuntimeABIParameter(name: "lambdaRaw", type: .intptr),
                RuntimeABIParameter(name: "captureRaw", type: .intptr),
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "Range"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_uint_range_foldIndexed",
            parameters: [
                RuntimeABIParameter(name: "rangeRaw", type: .intptr),
                RuntimeABIParameter(name: "initialValue", type: .intptr),
                RuntimeABIParameter(name: "lambdaRaw", type: .intptr),
                RuntimeABIParameter(name: "captureRaw", type: .intptr),
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "Range"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_uint_range_find",
            parameters: [
                RuntimeABIParameter(name: "rangeRaw", type: .intptr),
                RuntimeABIParameter(name: "lambdaRaw", type: .intptr),
                RuntimeABIParameter(name: "captureRaw", type: .intptr),
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "Range"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_uint_range_findLast",
            parameters: [
                RuntimeABIParameter(name: "rangeRaw", type: .intptr),
                RuntimeABIParameter(name: "lambdaRaw", type: .intptr),
                RuntimeABIParameter(name: "captureRaw", type: .intptr),
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "Range"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_uint_range_first_predicate",
            parameters: [
                RuntimeABIParameter(name: "rangeRaw", type: .intptr),
                RuntimeABIParameter(name: "lambdaRaw", type: .intptr),
                RuntimeABIParameter(name: "captureRaw", type: .intptr),
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "Range"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_uint_range_firstOrNull_predicate",
            parameters: [
                RuntimeABIParameter(name: "rangeRaw", type: .intptr),
                RuntimeABIParameter(name: "lambdaRaw", type: .intptr),
                RuntimeABIParameter(name: "captureRaw", type: .intptr),
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "Range"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_uint_range_firstOrNull",
            parameters: [
                RuntimeABIParameter(name: "rangeRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "Range"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_uint_range_last_predicate",
            parameters: [
                RuntimeABIParameter(name: "rangeRaw", type: .intptr),
                RuntimeABIParameter(name: "lambdaRaw", type: .intptr),
                RuntimeABIParameter(name: "captureRaw", type: .intptr),
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "Range"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_uint_range_lastOrNull_predicate",
            parameters: [
                RuntimeABIParameter(name: "rangeRaw", type: .intptr),
                RuntimeABIParameter(name: "lambdaRaw", type: .intptr),
                RuntimeABIParameter(name: "captureRaw", type: .intptr),
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "Range"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_uint_range_lastOrNull",
            parameters: [
                RuntimeABIParameter(name: "rangeRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "Range"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_uint_range_randomOrNull",
            parameters: [
                RuntimeABIParameter(name: "rangeRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "Range"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_uint_range_randomOrNull_random",
            parameters: [
                RuntimeABIParameter(name: "rangeRaw", type: .intptr),
                RuntimeABIParameter(name: "randomRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "Range"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_uint_range_random",
            parameters: [
                RuntimeABIParameter(name: "rangeRaw", type: .intptr),
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "Range"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_uint_range_random_random",
            parameters: [
                RuntimeABIParameter(name: "rangeRaw", type: .intptr),
                RuntimeABIParameter(name: "randomRaw", type: .intptr),
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "Range"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_uint_range_any",
            parameters: [
                RuntimeABIParameter(name: "rangeRaw", type: .intptr),
                RuntimeABIParameter(name: "lambdaRaw", type: .intptr),
                RuntimeABIParameter(name: "captureRaw", type: .intptr),
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "Range"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_uint_range_all",
            parameters: [
                RuntimeABIParameter(name: "rangeRaw", type: .intptr),
                RuntimeABIParameter(name: "lambdaRaw", type: .intptr),
                RuntimeABIParameter(name: "captureRaw", type: .intptr),
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "Range"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_uint_range_none",
            parameters: [
                RuntimeABIParameter(name: "rangeRaw", type: .intptr),
                RuntimeABIParameter(name: "lambdaRaw", type: .intptr),
                RuntimeABIParameter(name: "captureRaw", type: .intptr),
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "Range"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_uint_range_chunked",
            parameters: [
                RuntimeABIParameter(name: "rangeRaw", type: .intptr),
                RuntimeABIParameter(name: "size", type: .intptr),
            ],
            returnType: .intptr,
            section: "Range"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_uint_range_windowed",
            parameters: [
                RuntimeABIParameter(name: "rangeRaw", type: .intptr),
                RuntimeABIParameter(name: "size", type: .intptr),
                RuntimeABIParameter(name: "step", type: .intptr),
                RuntimeABIParameter(name: "partialWindows", type: .intptr),
            ],
            returnType: .intptr,
            section: "Range"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_ulong_range_contains",
            parameters: [
                RuntimeABIParameter(name: "rangeRaw", type: .intptr),
                RuntimeABIParameter(name: "value", type: .intptr),
            ],
            returnType: .intptr,
            section: "Range"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_ulong_range_first",
            parameters: [
                RuntimeABIParameter(name: "rangeRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "Range"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_ulong_range_last",
            parameters: [
                RuntimeABIParameter(name: "rangeRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "Range"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_ulong_range_step",
            parameters: [
                RuntimeABIParameter(name: "rangeRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "Range"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_ulong_range_isEmpty",
            parameters: [
                RuntimeABIParameter(name: "rangeRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "Range"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_ulong_range_toULongArray",
            parameters: [
                RuntimeABIParameter(name: "rangeRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "Range"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_ulong_range_mapIndexed",
            parameters: [
                RuntimeABIParameter(name: "rangeRaw", type: .intptr),
                RuntimeABIParameter(name: "lambdaRaw", type: .intptr),
                RuntimeABIParameter(name: "captureRaw", type: .intptr),
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "Range"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_ulong_range_mapNotNull",
            parameters: [
                RuntimeABIParameter(name: "rangeRaw", type: .intptr),
                RuntimeABIParameter(name: "lambdaRaw", type: .intptr),
                RuntimeABIParameter(name: "captureRaw", type: .intptr),
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "Range"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_ulong_range_filter",
            parameters: [
                RuntimeABIParameter(name: "rangeRaw", type: .intptr),
                RuntimeABIParameter(name: "lambdaRaw", type: .intptr),
                RuntimeABIParameter(name: "captureRaw", type: .intptr),
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "Range"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_ulong_range_filterIndexed",
            parameters: [
                RuntimeABIParameter(name: "rangeRaw", type: .intptr),
                RuntimeABIParameter(name: "lambdaRaw", type: .intptr),
                RuntimeABIParameter(name: "captureRaw", type: .intptr),
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "Range"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_ulong_range_filterNot",
            parameters: [
                RuntimeABIParameter(name: "rangeRaw", type: .intptr),
                RuntimeABIParameter(name: "lambdaRaw", type: .intptr),
                RuntimeABIParameter(name: "captureRaw", type: .intptr),
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "Range"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_ulong_range_reduce",
            parameters: [
                RuntimeABIParameter(name: "rangeRaw", type: .intptr),
                RuntimeABIParameter(name: "lambdaRaw", type: .intptr),
                RuntimeABIParameter(name: "captureRaw", type: .intptr),
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "Range"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_ulong_range_reduceIndexed",
            parameters: [
                RuntimeABIParameter(name: "rangeRaw", type: .intptr),
                RuntimeABIParameter(name: "lambdaRaw", type: .intptr),
                RuntimeABIParameter(name: "captureRaw", type: .intptr),
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "Range"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_ulong_range_fold",
            parameters: [
                RuntimeABIParameter(name: "rangeRaw", type: .intptr),
                RuntimeABIParameter(name: "initialValue", type: .intptr),
                RuntimeABIParameter(name: "lambdaRaw", type: .intptr),
                RuntimeABIParameter(name: "captureRaw", type: .intptr),
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "Range"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_ulong_range_foldIndexed",
            parameters: [
                RuntimeABIParameter(name: "rangeRaw", type: .intptr),
                RuntimeABIParameter(name: "initialValue", type: .intptr),
                RuntimeABIParameter(name: "lambdaRaw", type: .intptr),
                RuntimeABIParameter(name: "captureRaw", type: .intptr),
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "Range"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_ulong_range_find",
            parameters: [
                RuntimeABIParameter(name: "rangeRaw", type: .intptr),
                RuntimeABIParameter(name: "lambdaRaw", type: .intptr),
                RuntimeABIParameter(name: "captureRaw", type: .intptr),
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "Range"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_ulong_range_findLast",
            parameters: [
                RuntimeABIParameter(name: "rangeRaw", type: .intptr),
                RuntimeABIParameter(name: "lambdaRaw", type: .intptr),
                RuntimeABIParameter(name: "captureRaw", type: .intptr),
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "Range"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_ulong_range_first_predicate",
            parameters: [
                RuntimeABIParameter(name: "rangeRaw", type: .intptr),
                RuntimeABIParameter(name: "lambdaRaw", type: .intptr),
                RuntimeABIParameter(name: "captureRaw", type: .intptr),
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "Range"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_ulong_range_firstOrNull_predicate",
            parameters: [
                RuntimeABIParameter(name: "rangeRaw", type: .intptr),
                RuntimeABIParameter(name: "lambdaRaw", type: .intptr),
                RuntimeABIParameter(name: "captureRaw", type: .intptr),
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "Range"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_ulong_range_firstOrNull",
            parameters: [
                RuntimeABIParameter(name: "rangeRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "Range"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_ulong_range_last_predicate",
            parameters: [
                RuntimeABIParameter(name: "rangeRaw", type: .intptr),
                RuntimeABIParameter(name: "lambdaRaw", type: .intptr),
                RuntimeABIParameter(name: "captureRaw", type: .intptr),
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "Range"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_ulong_range_lastOrNull_predicate",
            parameters: [
                RuntimeABIParameter(name: "rangeRaw", type: .intptr),
                RuntimeABIParameter(name: "lambdaRaw", type: .intptr),
                RuntimeABIParameter(name: "captureRaw", type: .intptr),
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "Range"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_ulong_range_lastOrNull",
            parameters: [
                RuntimeABIParameter(name: "rangeRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "Range"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_ulong_range_randomOrNull",
            parameters: [
                RuntimeABIParameter(name: "rangeRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "Range"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_ulong_range_randomOrNull_random",
            parameters: [
                RuntimeABIParameter(name: "rangeRaw", type: .intptr),
                RuntimeABIParameter(name: "randomRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "Range"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_ulong_range_random",
            parameters: [
                RuntimeABIParameter(name: "rangeRaw", type: .intptr),
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "Range"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_ulong_range_random_random",
            parameters: [
                RuntimeABIParameter(name: "rangeRaw", type: .intptr),
                RuntimeABIParameter(name: "randomRaw", type: .intptr),
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "Range"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_ulong_range_any",
            parameters: [
                RuntimeABIParameter(name: "rangeRaw", type: .intptr),
                RuntimeABIParameter(name: "lambdaRaw", type: .intptr),
                RuntimeABIParameter(name: "captureRaw", type: .intptr),
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "Range"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_ulong_range_all",
            parameters: [
                RuntimeABIParameter(name: "rangeRaw", type: .intptr),
                RuntimeABIParameter(name: "lambdaRaw", type: .intptr),
                RuntimeABIParameter(name: "captureRaw", type: .intptr),
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "Range"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_ulong_range_none",
            parameters: [
                RuntimeABIParameter(name: "rangeRaw", type: .intptr),
                RuntimeABIParameter(name: "lambdaRaw", type: .intptr),
                RuntimeABIParameter(name: "captureRaw", type: .intptr),
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "Range"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_ulong_range_chunked",
            parameters: [
                RuntimeABIParameter(name: "rangeRaw", type: .intptr),
                RuntimeABIParameter(name: "size", type: .intptr),
            ],
            returnType: .intptr,
            section: "Range"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_ulong_range_windowed",
            parameters: [
                RuntimeABIParameter(name: "rangeRaw", type: .intptr),
                RuntimeABIParameter(name: "size", type: .intptr),
                RuntimeABIParameter(name: "step", type: .intptr),
                RuntimeABIParameter(name: "partialWindows", type: .intptr),
            ],
            returnType: .intptr,
            section: "Range"
        ),
    ]
}
