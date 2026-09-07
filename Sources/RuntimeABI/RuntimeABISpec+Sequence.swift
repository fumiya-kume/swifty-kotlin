// Sequence ABI specs (STDLIB-003)

public extension RuntimeABISpec {
    private static func stdlibSequenceHOFName(_ memberName: String, arity: Int, fallback: String) -> String {
        StdlibSurfaceSpec.collectionHOFRuntimeLinkName(
            ownerKind: .sequence,
            memberName: memberName,
            arity: arity,
            fallback: fallback
        )
    }

    /// Sequence functions for lazy evaluation chains.
    static let sequenceFunctions: [RuntimeABIFunctionSpec] = [
        // Sequence from List (asSequence)
        RuntimeABIFunctionSpec(
            name: "kk_sequence_from_list",
            parameters: [
                RuntimeABIParameter(name: "listRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "Sequence",
            isThrowing: false
        ),
        // Intermediate operations (lazy)
        RuntimeABIFunctionSpec(
            name: stdlibSequenceHOFName("map", arity: 1, fallback: "kk_sequence_map"),
            parameters: [
                RuntimeABIParameter(name: "seqRaw", type: .intptr),
                RuntimeABIParameter(name: "fnPtr", type: .intptr),
                RuntimeABIParameter(name: "closureRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "Sequence",
            isThrowing: false
        ),
        RuntimeABIFunctionSpec(
            name: stdlibSequenceHOFName("filter", arity: 1, fallback: "kk_sequence_filter"),
            parameters: [
                RuntimeABIParameter(name: "seqRaw", type: .intptr),
                RuntimeABIParameter(name: "fnPtr", type: .intptr),
                RuntimeABIParameter(name: "closureRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "Sequence",
            isThrowing: false
        ),
        RuntimeABIFunctionSpec(
            name: "kk_sequence_takeLast",
            parameters: [
                RuntimeABIParameter(name: "seqRaw", type: .intptr),
                RuntimeABIParameter(name: "count", type: .intptr),
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "Sequence"
        ),
        RuntimeABIFunctionSpec(
            name: stdlibSequenceHOFName("takeLastWhile", arity: 1, fallback: "kk_sequence_takeLastWhile"),
            parameters: [
                RuntimeABIParameter(name: "seqRaw", type: .intptr),
                RuntimeABIParameter(name: "fnPtr", type: .intptr),
                RuntimeABIParameter(name: "closureRaw", type: .intptr),
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "Sequence"
        ),
        // Terminal operations
        RuntimeABIFunctionSpec(
            name: "kk_sequence_to_list",
            parameters: [
                RuntimeABIParameter(name: "seqRaw", type: .intptr),
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "Sequence"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_sequence_constrainOnce",
            parameters: [
                RuntimeABIParameter(name: "seqRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "Sequence",
            isThrowing: false
        ),
        // Sequence builder
        RuntimeABIFunctionSpec(
            name: "__kk_sequence_builder_yield",
            parameters: [
                RuntimeABIParameter(name: "builderRaw", type: .intptr),
                RuntimeABIParameter(name: "value", type: .intptr),
            ],
            returnType: .intptr,
            section: "Sequence",
            isThrowing: false
        ),
        // STDLIB-553: yieldAll(iterable)
        RuntimeABIFunctionSpec(
            name: "__kk_sequence_builder_yieldAll",
            parameters: [
                RuntimeABIParameter(name: "builderRaw", type: .intptr),
                RuntimeABIParameter(name: "collectionRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "Sequence"
        ),
        RuntimeABIFunctionSpec(
            name: "__kk_sequence_builder_build",
            parameters: [
                RuntimeABIParameter(name: "fnPtr", type: .intptr),
                RuntimeABIParameter(name: "closureRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "Sequence",
            isThrowing: false
        ),
        RuntimeABIFunctionSpec(
            name: "__kk_sequence_builder_build_coro",
            parameters: [
                RuntimeABIParameter(name: "entryPointRaw", type: .intptr),
                RuntimeABIParameter(name: "functionID", type: .intptr),
                RuntimeABIParameter(name: "closureRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "Sequence",
            isThrowing: false
        ),
        // Iterator builder (STDLIB-331/564)
        RuntimeABIFunctionSpec(
            name: "__kk_iterator_builder_build",
            parameters: [
                RuntimeABIParameter(name: "fnPtr", type: .intptr),
            ],
            returnType: .intptr,
            section: "Sequence",
            isThrowing: false
        ),
        RuntimeABIFunctionSpec(
            name: "__kk_iterator_builder_build_coro",
            parameters: [
                RuntimeABIParameter(name: "entryPointRaw", type: .intptr),
                RuntimeABIParameter(name: "functionID", type: .intptr),
                RuntimeABIParameter(name: "closureRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "Sequence",
            isThrowing: false
        ),
        RuntimeABIFunctionSpec(
            name: "__kk_iterator_builder_yield",
            parameters: [
                RuntimeABIParameter(name: "builderRaw", type: .intptr),
                RuntimeABIParameter(name: "value", type: .intptr),
            ],
            returnType: .intptr,
            section: "Sequence"
        ),
        RuntimeABIFunctionSpec(
            name: "__kk_iterator_builder_hasNext",
            parameters: [
                RuntimeABIParameter(name: "iterRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "Sequence"
        ),
        RuntimeABIFunctionSpec(
            name: "__kk_iterator_builder_next",
            parameters: [
                RuntimeABIParameter(name: "iterRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "Sequence"
        ),
        // CORO-004 Phase 2: suspension-aware consumer API
        RuntimeABIFunctionSpec(
            name: "__kk_iterator_builder_hasNext_coro",
            parameters: [
                RuntimeABIParameter(name: "iterRaw", type: .intptr),
                RuntimeABIParameter(name: "continuationRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "Sequence"
        ),
        RuntimeABIFunctionSpec(
            name: "__kk_iterator_builder_next_coro",
            parameters: [
                RuntimeABIParameter(name: "iterRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "Sequence"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_sequence_completed_sentinel",
            parameters: [],
            returnType: .intptr,
            section: "Sequence",
            isThrowing: false
        ),
        // Factory functions (STDLIB-097)
        RuntimeABIFunctionSpec(
            name: "__kk_sequence_of",
            parameters: [
                RuntimeABIParameter(name: "arrayRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "Sequence",
            isThrowing: false
        ),
        RuntimeABIFunctionSpec(
            name: "kk_sequence_of_single",
            parameters: [
                RuntimeABIParameter(name: "element", type: .intptr),
            ],
            returnType: .intptr,
            section: "Sequence",
            isThrowing: false
        ),
        RuntimeABIFunctionSpec(
            name: "__kk_sequence_generate",
            parameters: [
                RuntimeABIParameter(name: "seed", type: .intptr),
                RuntimeABIParameter(name: "fnPtr", type: .intptr),
                RuntimeABIParameter(name: "closureRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "Sequence",
            isThrowing: false
        ),
        // STDLIB-SEQ-002: 1-arg form generateSequence(nextFunction: () -> T?)
        RuntimeABIFunctionSpec(
            name: "__kk_sequence_generate_noarg",
            parameters: [
                RuntimeABIParameter(name: "fnPtr", type: .intptr),
                RuntimeABIParameter(name: "closureRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "Sequence",
            isThrowing: false
        ),
        // Terminal operations (STDLIB-095) are source-backed in bundled Kotlin.
        RuntimeABIFunctionSpec(
            name: stdlibSequenceHOFName("flatMap", arity: 1, fallback: "kk_sequence_flatMap"),
            parameters: [
                RuntimeABIParameter(name: "seqRaw", type: .intptr),
                RuntimeABIParameter(name: "fnPtr", type: .intptr),
                RuntimeABIParameter(name: "closureRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "Sequence",
            isThrowing: false
        ),
        RuntimeABIFunctionSpec(
            name: stdlibSequenceHOFName("flatMapIndexed", arity: 1, fallback: "kk_sequence_flatMapIndexed"),
            parameters: [
                RuntimeABIParameter(name: "seqRaw", type: .intptr),
                RuntimeABIParameter(name: "fnPtr", type: .intptr),
                RuntimeABIParameter(name: "closureRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "Sequence",
            isThrowing: false
        ),
        // Intermediate operations (STDLIB-096)
        // Sorting operations (STDLIB-272)
        RuntimeABIFunctionSpec(
            name: "kk_sequence_sorted",
            parameters: [
                RuntimeABIParameter(name: "seqRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "Sequence",
            isThrowing: false
        ),
        RuntimeABIFunctionSpec(
            name: "kk_sequence_sortedBy",
            parameters: [
                RuntimeABIParameter(name: "seqRaw", type: .intptr),
                RuntimeABIParameter(name: "fnPtr", type: .intptr),
                RuntimeABIParameter(name: "closureRaw", type: .intptr),
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "Sequence"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_sequence_sortedByDescending",
            parameters: [
                RuntimeABIParameter(name: "seqRaw", type: .intptr),
                RuntimeABIParameter(name: "fnPtr", type: .intptr),
                RuntimeABIParameter(name: "closureRaw", type: .intptr),
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "Sequence"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_sequence_sortedDescending",
            parameters: [
                RuntimeABIParameter(name: "seqRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "Sequence",
            isThrowing: false
        ),
        // STDLIB-SEQ-019: shuffled / shuffled(random)
        RuntimeABIFunctionSpec(
            name: "kk_sequence_shuffled",
            parameters: [
                RuntimeABIParameter(name: "seqRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "Sequence",
            isThrowing: false
        ),
        RuntimeABIFunctionSpec(
            name: "kk_sequence_shuffled_random",
            parameters: [
                RuntimeABIParameter(name: "seqRaw", type: .intptr),
                RuntimeABIParameter(name: "randomRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "Sequence",
            isThrowing: false
        ),
        // Higher-order operations (STDLIB-271)
        RuntimeABIFunctionSpec(
            name: stdlibSequenceHOFName("mapNotNull", arity: 1, fallback: "kk_sequence_mapNotNull"),
            parameters: [
                RuntimeABIParameter(name: "seqRaw", type: .intptr),
                RuntimeABIParameter(name: "fnPtr", type: .intptr),
                RuntimeABIParameter(name: "closureRaw", type: .intptr),
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "Sequence"
        ),
        RuntimeABIFunctionSpec(
            name: stdlibSequenceHOFName("mapIndexedNotNull", arity: 1, fallback: "kk_sequence_mapIndexedNotNull"),
            parameters: [
                RuntimeABIParameter(name: "seqRaw", type: .intptr),
                RuntimeABIParameter(name: "fnPtr", type: .intptr),
                RuntimeABIParameter(name: "closureRaw", type: .intptr),
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "Sequence"
        ),
        RuntimeABIFunctionSpec(
            name: stdlibSequenceHOFName("firstNotNullOf", arity: 1, fallback: "kk_sequence_firstNotNullOf"),
            parameters: [
                RuntimeABIParameter(name: "seqRaw", type: .intptr),
                RuntimeABIParameter(name: "fnPtr", type: .intptr),
                RuntimeABIParameter(name: "closureRaw", type: .intptr),
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "Sequence"
        ),
        RuntimeABIFunctionSpec(
            name: stdlibSequenceHOFName(
                "firstNotNullOfOrNull",
                arity: 1,
                fallback: "kk_sequence_firstNotNullOfOrNull"
            ),
            parameters: [
                RuntimeABIParameter(name: "seqRaw", type: .intptr),
                RuntimeABIParameter(name: "fnPtr", type: .intptr),
                RuntimeABIParameter(name: "closureRaw", type: .intptr),
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "Sequence"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_sequence_filterNotNull",
            parameters: [
                RuntimeABIParameter(name: "seqRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "Sequence",
            isThrowing: false
        ),
        RuntimeABIFunctionSpec(
            name: "kk_sequence_requireNoNulls",
            parameters: [
                RuntimeABIParameter(name: "seqRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "Sequence",
            isThrowing: false
        ),
        RuntimeABIFunctionSpec(
            name: "kk_sequence_reversed",
            parameters: [
                RuntimeABIParameter(name: "seqRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "Sequence",
            isThrowing: false
        ),
        RuntimeABIFunctionSpec(
            name: stdlibSequenceHOFName("mapIndexed", arity: 1, fallback: "kk_sequence_mapIndexed"),
            parameters: [
                RuntimeABIParameter(name: "seqRaw", type: .intptr),
                RuntimeABIParameter(name: "fnPtr", type: .intptr),
                RuntimeABIParameter(name: "closureRaw", type: .intptr),
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "Sequence"
        ),
        RuntimeABIFunctionSpec(
            name: stdlibSequenceHOFName("filterIndexed", arity: 1, fallback: "kk_sequence_filterIndexed"),
            parameters: [
                RuntimeABIParameter(name: "seqRaw", type: .intptr),
                RuntimeABIParameter(name: "fnPtr", type: .intptr),
                RuntimeABIParameter(name: "closureRaw", type: .intptr),
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "Sequence"
        ),
        RuntimeABIFunctionSpec(
            name: stdlibSequenceHOFName("onEachIndexed", arity: 1, fallback: "kk_sequence_onEachIndexed"),
            parameters: [
                RuntimeABIParameter(name: "seqRaw", type: .intptr),
                RuntimeABIParameter(name: "fnPtr", type: .intptr),
                RuntimeABIParameter(name: "closureRaw", type: .intptr),
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "Sequence"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_sequence_withIndex",
            parameters: [
                RuntimeABIParameter(name: "seqRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "Sequence",
            isThrowing: false
        ),
        // STDLIB-275: joinTo/joinToString, sumOf, associate, associateBy
        // STDLIB-276: windowed, onEach
        // STDLIB-277: emptySequence / ifEmpty
        RuntimeABIFunctionSpec(
            name: "__kk_empty_sequence",
            parameters: [],
            returnType: .intptr,
            section: "Sequence",
            isThrowing: false,
        ),
        RuntimeABIFunctionSpec(
            name: stdlibSequenceHOFName("onEach", arity: 1, fallback: "kk_sequence_onEach"),
            parameters: [
                RuntimeABIParameter(name: "seqRaw", type: .intptr),
                RuntimeABIParameter(name: "fnPtr", type: .intptr),
                RuntimeABIParameter(name: "closureRaw", type: .intptr),
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "Sequence"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_sequence_ifEmpty",
            parameters: [
                RuntimeABIParameter(name: "seqRaw", type: .intptr),
                RuntimeABIParameter(name: "fnPtr", type: .intptr),
                RuntimeABIParameter(name: "closureRaw", type: .intptr),
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "Sequence"
        ),
        // Terminal operations (STDLIB-273)
        RuntimeABIFunctionSpec(
            name: "kk_sequence_first",
            parameters: [
                RuntimeABIParameter(name: "seqRaw", type: .intptr),
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "Sequence"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_sequence_firstOrNull",
            parameters: [
                RuntimeABIParameter(name: "seqRaw", type: .intptr),
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "Sequence"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_sequence_random",
            parameters: [
                RuntimeABIParameter(name: "seqRaw", type: .intptr),
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "Sequence"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_sequence_randomOrNull",
            parameters: [
                RuntimeABIParameter(name: "seqRaw", type: .intptr),
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "Sequence"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_sequence_last",
            parameters: [
                RuntimeABIParameter(name: "seqRaw", type: .intptr),
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "Sequence"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_sequence_lastOrNull",
            parameters: [
                RuntimeABIParameter(name: "seqRaw", type: .intptr),
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "Sequence"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_sequence_single",
            parameters: [
                RuntimeABIParameter(name: "seqRaw", type: .intptr),
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "Sequence"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_sequence_singleOrNull",
            parameters: [
                RuntimeABIParameter(name: "seqRaw", type: .intptr),
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "Sequence"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_sequence_count",
            parameters: [
                RuntimeABIParameter(name: "seqRaw", type: .intptr),
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "Sequence"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_sequence_contains",
            parameters: [
                RuntimeABIParameter(name: "seqRaw", type: .intptr),
                RuntimeABIParameter(name: "element", type: .intptr),
            ],
            returnType: .intptr,
            section: "Sequence"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_sequence_indexOf",
            parameters: [
                RuntimeABIParameter(name: "seqRaw", type: .intptr),
                RuntimeABIParameter(name: "element", type: .intptr),
            ],
            returnType: .intptr,
            section: "Sequence",
            isThrowing: false
        ),
        RuntimeABIFunctionSpec(
            name: "kk_sequence_indexOfFirst",
            parameters: [
                RuntimeABIParameter(name: "seqRaw", type: .intptr),
                RuntimeABIParameter(name: "fnPtr", type: .intptr),
                RuntimeABIParameter(name: "closureRaw", type: .intptr),
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "Sequence"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_sequence_lastIndexOf",
            parameters: [
                RuntimeABIParameter(name: "seqRaw", type: .intptr),
                RuntimeABIParameter(name: "element", type: .intptr),
            ],
            returnType: .intptr,
            section: "Sequence",
            isThrowing: false
        ),
        RuntimeABIFunctionSpec(
            name: "kk_sequence_indexOfLast",
            parameters: [
                RuntimeABIParameter(name: "seqRaw", type: .intptr),
                RuntimeABIParameter(name: "fnPtr", type: .intptr),
                RuntimeABIParameter(name: "closureRaw", type: .intptr),
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "Sequence"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_sequence_intersect",
            parameters: [
                RuntimeABIParameter(name: "seqRaw", type: .intptr),
                RuntimeABIParameter(name: "otherRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "Sequence",
            isThrowing: false
        ),
        RuntimeABIFunctionSpec(
            name: "kk_sequence_elementAtOrNull",
            parameters: [
                RuntimeABIParameter(name: "seqRaw", type: .intptr),
                RuntimeABIParameter(name: "index", type: .intptr),
            ],
            returnType: .intptr,
            section: "Sequence"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_sequence_elementAt",
            parameters: [
                RuntimeABIParameter(name: "seqRaw", type: .intptr),
                RuntimeABIParameter(name: "index", type: .intptr),
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "Sequence"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_sequence_elementAtOrElse",
            parameters: [
                RuntimeABIParameter(name: "seqRaw", type: .intptr),
                RuntimeABIParameter(name: "index", type: .intptr),
                RuntimeABIParameter(name: "fnPtr", type: .intptr),
                RuntimeABIParameter(name: "closureRaw", type: .intptr),
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "Sequence"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_sequence_sum",
            parameters: [
                RuntimeABIParameter(name: "seqRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "Sequence"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_sequence_average",
            parameters: [
                RuntimeABIParameter(name: "seqRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "Sequence"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_sequence_toMutableList",
            parameters: [
                RuntimeABIParameter(name: "seqRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "Sequence"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_sequence_toMutableSet",
            parameters: [
                RuntimeABIParameter(name: "seqRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "Sequence",
            isThrowing: false
        ),
        RuntimeABIFunctionSpec(
            name: "kk_sequence_toHashSet",
            parameters: [
                RuntimeABIParameter(name: "seqRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "Sequence",
            isThrowing: false
        ),
        RuntimeABIFunctionSpec(
            name: "kk_sequence_toCollection",
            parameters: [
                RuntimeABIParameter(name: "seqRaw", type: .intptr),
                RuntimeABIParameter(name: "destRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "Sequence",
            isThrowing: false
        ),
        RuntimeABIFunctionSpec(
            name: "kk_sequence_unzip",
            parameters: [
                RuntimeABIParameter(name: "seqRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "Sequence"
        ),
        // STDLIB-558, 559, 560: scan, runningFold, runningReduce
        RuntimeABIFunctionSpec(
            name: "kk_sequence_scan",
            parameters: [
                RuntimeABIParameter(name: "seqRaw", type: .intptr),
                RuntimeABIParameter(name: "initial", type: .intptr),
                RuntimeABIParameter(name: "fnPtr", type: .intptr),
                RuntimeABIParameter(name: "closureRaw", type: .intptr),
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "Sequence"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_sequence_runningFold",
            parameters: [
                RuntimeABIParameter(name: "seqRaw", type: .intptr),
                RuntimeABIParameter(name: "initial", type: .intptr),
                RuntimeABIParameter(name: "fnPtr", type: .intptr),
                RuntimeABIParameter(name: "closureRaw", type: .intptr),
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "Sequence"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_sequence_runningReduce",
            parameters: [
                RuntimeABIParameter(name: "seqRaw", type: .intptr),
                RuntimeABIParameter(name: "fnPtr", type: .intptr),
                RuntimeABIParameter(name: "closureRaw", type: .intptr),
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "Sequence"
        ),
        // STDLIB-SEQ-017: runningReduceIndexed
        RuntimeABIFunctionSpec(
            name: "kk_sequence_runningReduceIndexed",
            parameters: [
                RuntimeABIParameter(name: "seqRaw", type: .intptr),
                RuntimeABIParameter(name: "fnPtr", type: .intptr),
                RuntimeABIParameter(name: "closureRaw", type: .intptr),
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "Sequence"
        ),
        // STDLIB-470: toSet, toMap, groupBy, maxOrNull, minOrNull, flatten
        RuntimeABIFunctionSpec(
            name: "kk_sequence_toSet",
            parameters: [
                RuntimeABIParameter(name: "seqRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "Sequence",
            isThrowing: false
        ),
        RuntimeABIFunctionSpec(
            name: "kk_sequence_toSortedSet",
            parameters: [
                RuntimeABIParameter(name: "seqRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "Sequence",
            isThrowing: false
        ),
        RuntimeABIFunctionSpec(
            name: "kk_sequence_toMap",
            parameters: [
                RuntimeABIParameter(name: "seqRaw", type: .intptr),
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "Sequence"
        ),
        RuntimeABIFunctionSpec(
            name: stdlibSequenceHOFName("groupBy", arity: 1, fallback: "kk_sequence_groupBy"),
            parameters: [
                RuntimeABIParameter(name: "seqRaw", type: .intptr),
                RuntimeABIParameter(name: "fnPtr", type: .intptr),
                RuntimeABIParameter(name: "closureRaw", type: .intptr),
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "Sequence"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_sequence_max",
            parameters: [
                RuntimeABIParameter(name: "seqRaw", type: .intptr),
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "Sequence"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_sequence_maxOrNull",
            parameters: [
                RuntimeABIParameter(name: "seqRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "Sequence",
            isThrowing: false
        ),
        RuntimeABIFunctionSpec(
            name: "kk_sequence_minOrNull",
            parameters: [
                RuntimeABIParameter(name: "seqRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "Sequence",
            isThrowing: false
        ),
        RuntimeABIFunctionSpec(
            name: "kk_sequence_min",
            parameters: [
                RuntimeABIParameter(name: "seqRaw", type: .intptr),
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "Sequence"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_sequence_flatten",
            parameters: [
                RuntimeABIParameter(name: "seqRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "Sequence",
            isThrowing: false
        ),
        // STDLIB-557: foldIndexed
        RuntimeABIFunctionSpec(
            name: "kk_sequence_foldIndexed",
            parameters: [
                RuntimeABIParameter(name: "seqRaw", type: .intptr),
                RuntimeABIParameter(name: "initial", type: .intptr),
                RuntimeABIParameter(name: "fnPtr", type: .intptr),
                RuntimeABIParameter(name: "closureRaw", type: .intptr),
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "Sequence"
        ),
        // STDLIB-SEQ-016: runningFoldIndexed, scanIndexed
        RuntimeABIFunctionSpec(
            name: "kk_sequence_runningFoldIndexed",
            parameters: [
                RuntimeABIParameter(name: "seqRaw", type: .intptr),
                RuntimeABIParameter(name: "initial", type: .intptr),
                RuntimeABIParameter(name: "fnPtr", type: .intptr),
                RuntimeABIParameter(name: "closureRaw", type: .intptr),
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "Sequence"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_sequence_scanIndexed",
            parameters: [
                RuntimeABIParameter(name: "seqRaw", type: .intptr),
                RuntimeABIParameter(name: "initial", type: .intptr),
                RuntimeABIParameter(name: "fnPtr", type: .intptr),
                RuntimeABIParameter(name: "closureRaw", type: .intptr),
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "Sequence"
        ),
        // STDLIB-556: reduceIndexed
        RuntimeABIFunctionSpec(
            name: "kk_sequence_reduceIndexed",
            parameters: [
                RuntimeABIParameter(name: "seqRaw", type: .intptr),
                RuntimeABIParameter(name: "fnPtr", type: .intptr),
                RuntimeABIParameter(name: "closureRaw", type: .intptr),
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "Sequence"
        ),
        // STDLIB-SEQ-015: reduceIndexedOrNull
        RuntimeABIFunctionSpec(
            name: "kk_sequence_reduceIndexedOrNull",
            parameters: [
                RuntimeABIParameter(name: "seqRaw", type: .intptr),
                RuntimeABIParameter(name: "fnPtr", type: .intptr),
                RuntimeABIParameter(name: "closureRaw", type: .intptr),
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "Sequence"
        ),
        // STDLIB-SEQ-FN-091: reduce
        RuntimeABIFunctionSpec(
            name: "kk_sequence_reduce",
            parameters: [
                RuntimeABIParameter(name: "seqRaw", type: .intptr),
                RuntimeABIParameter(name: "fnPtr", type: .intptr),
                RuntimeABIParameter(name: "closureRaw", type: .intptr),
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "Sequence"
        ),
        // STDLIB-SEQ-FN-093: reduceOrNull
        RuntimeABIFunctionSpec(
            name: "kk_sequence_reduceOrNull",
            parameters: [
                RuntimeABIParameter(name: "seqRaw", type: .intptr),
                RuntimeABIParameter(name: "fnPtr", type: .intptr),
                RuntimeABIParameter(name: "closureRaw", type: .intptr),
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "Sequence"
        ),
        // STDLIB-SEQ-FN-094: reduceRight
        RuntimeABIFunctionSpec(
            name: "kk_sequence_reduceRight",
            parameters: [
                RuntimeABIParameter(name: "seqRaw", type: .intptr),
                RuntimeABIParameter(name: "fnPtr", type: .intptr),
                RuntimeABIParameter(name: "closureRaw", type: .intptr),
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "Sequence"
        ),
        // STDLIB-SEQ-FN-095: reduceRightIndexed
        RuntimeABIFunctionSpec(
            name: "kk_sequence_reduceRightIndexed",
            parameters: [
                RuntimeABIParameter(name: "seqRaw", type: .intptr),
                RuntimeABIParameter(name: "fnPtr", type: .intptr),
                RuntimeABIParameter(name: "closureRaw", type: .intptr),
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "Sequence"
        ),
        // STDLIB-SEQ-FN-096: reduceRightIndexedOrNull
        RuntimeABIFunctionSpec(
            name: "kk_sequence_reduceRightIndexedOrNull",
            parameters: [
                RuntimeABIParameter(name: "seqRaw", type: .intptr),
                RuntimeABIParameter(name: "fnPtr", type: .intptr),
                RuntimeABIParameter(name: "closureRaw", type: .intptr),
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "Sequence"
        ),
        // STDLIB-SEQ-FN-097: reduceRightOrNull
        RuntimeABIFunctionSpec(
            name: "kk_sequence_reduceRightOrNull",
            parameters: [
                RuntimeABIParameter(name: "seqRaw", type: .intptr),
                RuntimeABIParameter(name: "fnPtr", type: .intptr),
                RuntimeABIParameter(name: "closureRaw", type: .intptr),
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "Sequence"
        ),
        // STDLIB-561: Sequence.plus(other)
        RuntimeABIFunctionSpec(
            name: "kk_sequence_plus",
            parameters: [
                RuntimeABIParameter(name: "seqRaw", type: .intptr),
                RuntimeABIParameter(name: "otherRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "Sequence",
            isThrowing: false
        ),
        // STDLIB-SEQ-013: Sequence.plus(element) / plusElement(element)
        RuntimeABIFunctionSpec(
            name: "kk_sequence_plus_element",
            parameters: [
                RuntimeABIParameter(name: "seqRaw", type: .intptr),
                RuntimeABIParameter(name: "element", type: .intptr),
            ],
            returnType: .intptr,
            section: "Sequence",
            isThrowing: false
        ),
        // STDLIB-562: Sequence.minus(element)
        RuntimeABIFunctionSpec(
            name: "kk_sequence_minus",
            parameters: [
                RuntimeABIParameter(name: "seqRaw", type: .intptr),
                RuntimeABIParameter(name: "element", type: .intptr),
            ],
            returnType: .intptr,
            section: "Sequence",
            isThrowing: false
        ),
        // STDLIB-SEQ-FN-130: Sequence.union(other)
        RuntimeABIFunctionSpec(
            name: "kk_sequence_union",
            parameters: [
                RuntimeABIParameter(name: "seqRaw", type: .intptr),
                RuntimeABIParameter(name: "otherRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "Sequence",
            isThrowing: false
        ),
        // STDLIB-SEQ-FN-115: Sequence.subtract(other)
        RuntimeABIFunctionSpec(
            name: "kk_sequence_subtract",
            parameters: [
                RuntimeABIParameter(name: "seqRaw", type: .intptr),
                RuntimeABIParameter(name: "otherRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "Sequence",
            isThrowing: false
        ),
        // STDLIB-SEQ-007: any/all/none/find with short-circuit semantics
        RuntimeABIFunctionSpec(
            name: "kk_sequence_any",
            parameters: [
                RuntimeABIParameter(name: "seqRaw", type: .intptr),
                RuntimeABIParameter(name: "fnPtr", type: .intptr),
                RuntimeABIParameter(name: "closureRaw", type: .intptr),
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "Sequence"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_sequence_all",
            parameters: [
                RuntimeABIParameter(name: "seqRaw", type: .intptr),
                RuntimeABIParameter(name: "fnPtr", type: .intptr),
                RuntimeABIParameter(name: "closureRaw", type: .intptr),
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "Sequence"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_sequence_none",
            parameters: [
                RuntimeABIParameter(name: "seqRaw", type: .intptr),
                RuntimeABIParameter(name: "fnPtr", type: .intptr),
                RuntimeABIParameter(name: "closureRaw", type: .intptr),
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "Sequence"
        ),
        // Runtime-backed Sequence / Iterator itable bridges (STDLIB-ARTIFACT-019)
        RuntimeABIFunctionSpec(
            name: "kk_sequence_box_iterator",
            parameters: [
                RuntimeABIParameter(name: "seqRaw", type: .intptr),
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "Sequence",
            isThrowing: false
        ),
        RuntimeABIFunctionSpec(
            name: "kk_sequence_iterator_hasNext",
            parameters: [
                RuntimeABIParameter(name: "iterRaw", type: .intptr),
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "Sequence",
            isThrowing: false
        ),
        RuntimeABIFunctionSpec(
            name: "kk_sequence_iterator_next",
            parameters: [
                RuntimeABIParameter(name: "iterRaw", type: .intptr),
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "Sequence",
            isThrowing: false
        ),
    ]
}
