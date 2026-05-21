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
            section: "Sequence"
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
            section: "Sequence"
        ),
        RuntimeABIFunctionSpec(
            name: stdlibSequenceHOFName("filter", arity: 1, fallback: "kk_sequence_filter"),
            parameters: [
                RuntimeABIParameter(name: "seqRaw", type: .intptr),
                RuntimeABIParameter(name: "fnPtr", type: .intptr),
                RuntimeABIParameter(name: "closureRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "Sequence"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_sequence_take",
            parameters: [
                RuntimeABIParameter(name: "seqRaw", type: .intptr),
                RuntimeABIParameter(name: "count", type: .intptr),
            ],
            returnType: .intptr,
            section: "Sequence"
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
            section: "Sequence"
        ),
        // Sequence builder
        RuntimeABIFunctionSpec(
            name: "kk_sequence_builder_create",
            parameters: [],
            returnType: .intptr,
            section: "Sequence"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_sequence_builder_yield",
            parameters: [
                RuntimeABIParameter(name: "builderRaw", type: .intptr),
                RuntimeABIParameter(name: "value", type: .intptr),
            ],
            returnType: .intptr,
            section: "Sequence"
        ),
        // STDLIB-553: yieldAll(iterable)
        RuntimeABIFunctionSpec(
            name: "kk_sequence_builder_yieldAll",
            parameters: [
                RuntimeABIParameter(name: "builderRaw", type: .intptr),
                RuntimeABIParameter(name: "collectionRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "Sequence"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_sequence_builder_build",
            parameters: [
                RuntimeABIParameter(name: "fnPtr", type: .intptr),
                RuntimeABIParameter(name: "closureRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "Sequence"
        ),
        // Iterator builder (STDLIB-331/564)
        RuntimeABIFunctionSpec(
            name: "kk_iterator_builder_build",
            parameters: [
                RuntimeABIParameter(name: "fnPtr", type: .intptr),
            ],
            returnType: .intptr,
            section: "Sequence"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_iterator_builder_yield",
            parameters: [
                RuntimeABIParameter(name: "builderRaw", type: .intptr),
                RuntimeABIParameter(name: "value", type: .intptr),
            ],
            returnType: .intptr,
            section: "Sequence"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_iterator_builder_hasNext",
            parameters: [
                RuntimeABIParameter(name: "iterRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "Sequence"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_iterator_builder_next",
            parameters: [
                RuntimeABIParameter(name: "iterRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "Sequence"
        ),
        // Factory functions (STDLIB-097)
        RuntimeABIFunctionSpec(
            name: "kk_sequence_of",
            parameters: [
                RuntimeABIParameter(name: "arrayRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "Sequence"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_sequence_of_single",
            parameters: [
                RuntimeABIParameter(name: "element", type: .intptr),
            ],
            returnType: .intptr,
            section: "Sequence"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_sequence_generate",
            parameters: [
                RuntimeABIParameter(name: "seed", type: .intptr),
                RuntimeABIParameter(name: "fnPtr", type: .intptr),
                RuntimeABIParameter(name: "closureRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "Sequence"
        ),
        // STDLIB-SEQ-002: 1-arg form generateSequence(nextFunction: () -> T?)
        RuntimeABIFunctionSpec(
            name: "kk_sequence_generate_noarg",
            parameters: [
                RuntimeABIParameter(name: "fnPtr", type: .intptr),
                RuntimeABIParameter(name: "closureRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "Sequence"
        ),
        // Terminal operations (STDLIB-095)
        RuntimeABIFunctionSpec(
            name: stdlibSequenceHOFName("forEach", arity: 1, fallback: "kk_sequence_forEach"),
            parameters: [
                RuntimeABIParameter(name: "seqRaw", type: .intptr),
                RuntimeABIParameter(name: "fnPtr", type: .intptr),
                RuntimeABIParameter(name: "closureRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "Sequence"
        ),
        RuntimeABIFunctionSpec(
            name: stdlibSequenceHOFName("forEachIndexed", arity: 1, fallback: "kk_sequence_forEachIndexed"),
            parameters: [
                RuntimeABIParameter(name: "seqRaw", type: .intptr),
                RuntimeABIParameter(name: "fnPtr", type: .intptr),
                RuntimeABIParameter(name: "closureRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "Sequence"
        ),
        RuntimeABIFunctionSpec(
            name: stdlibSequenceHOFName("flatMap", arity: 1, fallback: "kk_sequence_flatMap"),
            parameters: [
                RuntimeABIParameter(name: "seqRaw", type: .intptr),
                RuntimeABIParameter(name: "fnPtr", type: .intptr),
                RuntimeABIParameter(name: "closureRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "Sequence"
        ),
        RuntimeABIFunctionSpec(
            name: stdlibSequenceHOFName("flatMapIndexed", arity: 1, fallback: "kk_sequence_flatMapIndexed"),
            parameters: [
                RuntimeABIParameter(name: "seqRaw", type: .intptr),
                RuntimeABIParameter(name: "fnPtr", type: .intptr),
                RuntimeABIParameter(name: "closureRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "Sequence"
        ),
        // Intermediate operations (STDLIB-096)
        RuntimeABIFunctionSpec(
            name: "kk_sequence_drop",
            parameters: [
                RuntimeABIParameter(name: "seqRaw", type: .intptr),
                RuntimeABIParameter(name: "count", type: .intptr),
            ],
            returnType: .intptr,
            section: "Sequence"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_sequence_distinct",
            parameters: [
                RuntimeABIParameter(name: "seqRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "Sequence"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_sequence_distinctBy",
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
            name: "kk_sequence_zip",
            parameters: [
                RuntimeABIParameter(name: "seqRaw", type: .intptr),
                RuntimeABIParameter(name: "otherRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "Sequence"
        ),
        // Sorting operations (STDLIB-272)
        RuntimeABIFunctionSpec(
            name: "kk_sequence_sorted",
            parameters: [
                RuntimeABIParameter(name: "seqRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "Sequence"
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
            name: "kk_sequence_sortedDescending",
            parameters: [
                RuntimeABIParameter(name: "seqRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "Sequence"
        ),
        // STDLIB-SEQ-019: shuffled / shuffled(random)
        RuntimeABIFunctionSpec(
            name: "kk_sequence_shuffled",
            parameters: [
                RuntimeABIParameter(name: "seqRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "Sequence"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_sequence_shuffled_random",
            parameters: [
                RuntimeABIParameter(name: "seqRaw", type: .intptr),
                RuntimeABIParameter(name: "randomRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "Sequence"
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
            section: "Sequence"
        ),
        RuntimeABIFunctionSpec(
            name: stdlibSequenceHOFName("filterIsInstance", arity: 0, fallback: "kk_sequence_filterIsInstance"),
            parameters: [
                RuntimeABIParameter(name: "seqRaw", type: .intptr),
                RuntimeABIParameter(name: "typeToken", type: .intptr),
            ],
            returnType: .intptr,
            section: "Sequence"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_sequence_requireNoNulls",
            parameters: [
                RuntimeABIParameter(name: "seqRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "Sequence"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_sequence_reversed",
            parameters: [
                RuntimeABIParameter(name: "seqRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "Sequence"
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
            section: "Sequence"
        ),
        // STDLIB-275: joinTo/joinToString, sumOf, associate, associateBy
        RuntimeABIFunctionSpec(
            name: "kk_sequence_joinTo",
            parameters: [
                RuntimeABIParameter(name: "seqRaw", type: .intptr),
                RuntimeABIParameter(name: "destinationRaw", type: .intptr),
                RuntimeABIParameter(name: "separatorRaw", type: .intptr),
                RuntimeABIParameter(name: "prefixRaw", type: .intptr),
                RuntimeABIParameter(name: "postfixRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "Sequence"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_sequence_joinToString",
            parameters: [
                RuntimeABIParameter(name: "seqRaw", type: .intptr),
                RuntimeABIParameter(name: "separatorRaw", type: .intptr),
                RuntimeABIParameter(name: "prefixRaw", type: .intptr),
                RuntimeABIParameter(name: "postfixRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "Sequence"
        ),
        RuntimeABIFunctionSpec(
            name: stdlibSequenceHOFName("sumOf", arity: 1, fallback: "kk_sequence_sumOf"),
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
            name: stdlibSequenceHOFName("sumBy", arity: 1, fallback: "kk_sequence_sumBy"),
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
            name: stdlibSequenceHOFName("sumByDouble", arity: 1, fallback: "kk_sequence_sumByDouble"),
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
            name: stdlibSequenceHOFName("associate", arity: 1, fallback: "kk_sequence_associate"),
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
            name: stdlibSequenceHOFName("associateTo", arity: 2, fallback: "kk_sequence_associateTo"),
            parameters: [
                RuntimeABIParameter(name: "seqRaw", type: .intptr),
                RuntimeABIParameter(name: "destRaw", type: .intptr),
                RuntimeABIParameter(name: "fnPtr", type: .intptr),
                RuntimeABIParameter(name: "closureRaw", type: .intptr),
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "Sequence"
        ),
        RuntimeABIFunctionSpec(
            name: stdlibSequenceHOFName("associateBy", arity: 1, fallback: "kk_sequence_associateBy"),
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
            name: stdlibSequenceHOFName("associateByTo", arity: 2, fallback: "kk_sequence_associateByTo"),
            parameters: [
                RuntimeABIParameter(name: "seqRaw", type: .intptr),
                RuntimeABIParameter(name: "destRaw", type: .intptr),
                RuntimeABIParameter(name: "fnPtr", type: .intptr),
                RuntimeABIParameter(name: "closureRaw", type: .intptr),
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "Sequence"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_sequence_partition",
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
            name: stdlibSequenceHOFName("associateWith", arity: 1, fallback: "kk_sequence_associateWith"),
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
            name: stdlibSequenceHOFName("associateWithTo", arity: 2, fallback: "kk_sequence_associateWithTo"),
            parameters: [
                RuntimeABIParameter(name: "seqRaw", type: .intptr),
                RuntimeABIParameter(name: "destRaw", type: .intptr),
                RuntimeABIParameter(name: "fnPtr", type: .intptr),
                RuntimeABIParameter(name: "closureRaw", type: .intptr),
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "Sequence"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_sequence_minByOrNull",
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
            name: "kk_sequence_maxBy",
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
            name: "kk_sequence_maxByOrNull",
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
            name: "kk_sequence_maxWithOrNull",
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
            name: "kk_sequence_minOf",
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
            name: "kk_sequence_minOfOrNull",
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
            name: "kk_sequence_maxOfOrNull",
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
            name: "kk_sequence_maxOf",
            parameters: [
                RuntimeABIParameter(name: "seqRaw", type: .intptr),
                RuntimeABIParameter(name: "fnPtr", type: .intptr),
                RuntimeABIParameter(name: "closureRaw", type: .intptr),
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "Sequence"
        ),
        // STDLIB-276: chunked, windowed, onEach
        RuntimeABIFunctionSpec(
            name: "kk_sequence_chunked",
            parameters: [
                RuntimeABIParameter(name: "seqRaw", type: .intptr),
                RuntimeABIParameter(name: "size", type: .intptr),
            ],
            returnType: .intptr,
            section: "Sequence"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_sequence_chunked_transform",
            parameters: [
                RuntimeABIParameter(name: "seqRaw", type: .intptr),
                RuntimeABIParameter(name: "size", type: .intptr),
                RuntimeABIParameter(name: "fnPtr", type: .intptr),
                RuntimeABIParameter(name: "closureRaw", type: .intptr),
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "Sequence"
        ),
        // STDLIB-277: emptySequence / ifEmpty
        RuntimeABIFunctionSpec(
            name: "kk_empty_sequence",
            parameters: [],
            returnType: .intptr,
            section: "Sequence"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_sequence_orEmpty",
            parameters: [
                RuntimeABIParameter(name: "seqRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "Sequence"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_sequence_windowed",
            parameters: [
                RuntimeABIParameter(name: "seqRaw", type: .intptr),
                RuntimeABIParameter(name: "size", type: .intptr),
                RuntimeABIParameter(name: "step", type: .intptr),
                RuntimeABIParameter(name: "partialWindows", type: .intptr),
            ],
            returnType: .intptr,
            section: "Sequence"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_sequence_windowed_transform",
            parameters: [
                RuntimeABIParameter(name: "seqRaw", type: .intptr),
                RuntimeABIParameter(name: "size", type: .intptr),
                RuntimeABIParameter(name: "step", type: .intptr),
                RuntimeABIParameter(name: "partialWindows", type: .intptr),
                RuntimeABIParameter(name: "fnPtr", type: .intptr),
                RuntimeABIParameter(name: "closureRaw", type: .intptr),
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "Sequence"
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
            name: StdlibSurfaceSpec.collectionHOFRuntimeLinkName(
                ownerKind: .sequence,
                memberName: "filterTo",
                arity: 2,
                fallback: "kk_sequence_filterTo"
            ),
            parameters: [
                RuntimeABIParameter(name: "seqRaw", type: .intptr),
                RuntimeABIParameter(name: "destRaw", type: .intptr),
                RuntimeABIParameter(name: "fnPtr", type: .intptr),
                RuntimeABIParameter(name: "closureRaw", type: .intptr),
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "Sequence"
        ),
        RuntimeABIFunctionSpec(
            name: StdlibSurfaceSpec.collectionHOFRuntimeLinkName(
                ownerKind: .sequence,
                memberName: "filterNotTo",
                arity: 2,
                fallback: "kk_sequence_filterNotTo"
            ),
            parameters: [
                RuntimeABIParameter(name: "seqRaw", type: .intptr),
                RuntimeABIParameter(name: "destRaw", type: .intptr),
                RuntimeABIParameter(name: "fnPtr", type: .intptr),
                RuntimeABIParameter(name: "closureRaw", type: .intptr),
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "Sequence"
        ),
        RuntimeABIFunctionSpec(
            name: StdlibSurfaceSpec.collectionHOFRuntimeLinkName(
                ownerKind: .sequence,
                memberName: "mapTo",
                arity: 2,
                fallback: "kk_sequence_mapTo"
            ),
            parameters: [
                RuntimeABIParameter(name: "seqRaw", type: .intptr),
                RuntimeABIParameter(name: "destRaw", type: .intptr),
                RuntimeABIParameter(name: "fnPtr", type: .intptr),
                RuntimeABIParameter(name: "closureRaw", type: .intptr),
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "Sequence"
        ),
        RuntimeABIFunctionSpec(
            name: StdlibSurfaceSpec.collectionHOFRuntimeLinkName(
                ownerKind: .sequence,
                memberName: "flatMapTo",
                arity: 2,
                fallback: "kk_sequence_flatMapTo"
            ),
            parameters: [
                RuntimeABIParameter(name: "seqRaw", type: .intptr),
                RuntimeABIParameter(name: "destRaw", type: .intptr),
                RuntimeABIParameter(name: "fnPtr", type: .intptr),
                RuntimeABIParameter(name: "closureRaw", type: .intptr),
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "Sequence"
        ),
        RuntimeABIFunctionSpec(
            name: StdlibSurfaceSpec.collectionHOFRuntimeLinkName(
                ownerKind: .sequence,
                memberName: "filterIndexedTo",
                arity: 2,
                fallback: "kk_sequence_filterIndexedTo"
            ),
            parameters: [
                RuntimeABIParameter(name: "seqRaw", type: .intptr),
                RuntimeABIParameter(name: "destRaw", type: .intptr),
                RuntimeABIParameter(name: "fnPtr", type: .intptr),
                RuntimeABIParameter(name: "closureRaw", type: .intptr),
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "Sequence"
        ),
        RuntimeABIFunctionSpec(
            name: StdlibSurfaceSpec.collectionHOFRuntimeLinkName(
                ownerKind: .sequence,
                memberName: "mapNotNullTo",
                arity: 2,
                fallback: "kk_sequence_mapNotNullTo"
            ),
            parameters: [
                RuntimeABIParameter(name: "seqRaw", type: .intptr),
                RuntimeABIParameter(name: "destRaw", type: .intptr),
                RuntimeABIParameter(name: "fnPtr", type: .intptr),
                RuntimeABIParameter(name: "closureRaw", type: .intptr),
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "Sequence"
        ),
        RuntimeABIFunctionSpec(
            name: StdlibSurfaceSpec.collectionHOFRuntimeLinkName(
                ownerKind: .sequence,
                memberName: "mapIndexedNotNullTo",
                arity: 2,
                fallback: "kk_sequence_mapIndexedNotNullTo"
            ),
            parameters: [
                RuntimeABIParameter(name: "seqRaw", type: .intptr),
                RuntimeABIParameter(name: "destRaw", type: .intptr),
                RuntimeABIParameter(name: "fnPtr", type: .intptr),
                RuntimeABIParameter(name: "closureRaw", type: .intptr),
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "Sequence"
        ),
        RuntimeABIFunctionSpec(
            name: StdlibSurfaceSpec.collectionHOFRuntimeLinkName(
                ownerKind: .sequence,
                memberName: "flatMapIndexedTo",
                arity: 2,
                fallback: "kk_sequence_flatMapIndexedTo"
            ),
            parameters: [
                RuntimeABIParameter(name: "seqRaw", type: .intptr),
                RuntimeABIParameter(name: "destRaw", type: .intptr),
                RuntimeABIParameter(name: "fnPtr", type: .intptr),
                RuntimeABIParameter(name: "closureRaw", type: .intptr),
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "Sequence"
        ),
        RuntimeABIFunctionSpec(
            name: StdlibSurfaceSpec.collectionHOFRuntimeLinkName(
                ownerKind: .sequence,
                memberName: "filterNotNullTo",
                arity: 1,
                fallback: "kk_sequence_filterNotNullTo"
            ),
            parameters: [
                RuntimeABIParameter(name: "seqRaw", type: .intptr),
                RuntimeABIParameter(name: "destRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "Sequence"
        ),
        RuntimeABIFunctionSpec(
            name: StdlibSurfaceSpec.collectionHOFRuntimeLinkName(
                ownerKind: .sequence,
                memberName: "filterIsInstanceTo",
                arity: 1,
                fallback: "kk_sequence_filterIsInstanceTo"
            ),
            parameters: [
                RuntimeABIParameter(name: "seqRaw", type: .intptr),
                RuntimeABIParameter(name: "destRaw", type: .intptr),
                RuntimeABIParameter(name: "typeToken", type: .intptr),
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
            name: "kk_sequence_findLast",
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
            section: "Sequence"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_sequence_intersect",
            parameters: [
                RuntimeABIParameter(name: "seqRaw", type: .intptr),
                RuntimeABIParameter(name: "otherRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "Sequence"
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
            section: "Sequence"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_sequence_toHashSet",
            parameters: [
                RuntimeABIParameter(name: "seqRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "Sequence"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_sequence_toCollection",
            parameters: [
                RuntimeABIParameter(name: "seqRaw", type: .intptr),
                RuntimeABIParameter(name: "destRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "Sequence"
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
            section: "Sequence"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_sequence_toSortedSet",
            parameters: [
                RuntimeABIParameter(name: "seqRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "Sequence"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_sequence_toMap",
            parameters: [
                RuntimeABIParameter(name: "seqRaw", type: .intptr),
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
            name: stdlibSequenceHOFName("groupByTo", arity: 2, fallback: "kk_sequence_groupByTo"),
            parameters: [
                RuntimeABIParameter(name: "seqRaw", type: .intptr),
                RuntimeABIParameter(name: "destRaw", type: .intptr),
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
            section: "Sequence"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_sequence_minOrNull",
            parameters: [
                RuntimeABIParameter(name: "seqRaw", type: .intptr),
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
            section: "Sequence"
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
        // STDLIB-561: Sequence.plus(other)
        RuntimeABIFunctionSpec(
            name: "kk_sequence_plus",
            parameters: [
                RuntimeABIParameter(name: "seqRaw", type: .intptr),
                RuntimeABIParameter(name: "otherRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "Sequence"
        ),
        // STDLIB-SEQ-013: Sequence.plus(element) / plusElement(element)
        RuntimeABIFunctionSpec(
            name: "kk_sequence_plus_element",
            parameters: [
                RuntimeABIParameter(name: "seqRaw", type: .intptr),
                RuntimeABIParameter(name: "element", type: .intptr),
            ],
            returnType: .intptr,
            section: "Sequence"
        ),
        // STDLIB-562: Sequence.minus(element)
        RuntimeABIFunctionSpec(
            name: "kk_sequence_minus",
            parameters: [
                RuntimeABIParameter(name: "seqRaw", type: .intptr),
                RuntimeABIParameter(name: "element", type: .intptr),
            ],
            returnType: .intptr,
            section: "Sequence"
        ),
        // STDLIB-SEQ-FN-130: Sequence.union(other)
        RuntimeABIFunctionSpec(
            name: "kk_sequence_union",
            parameters: [
                RuntimeABIParameter(name: "seqRaw", type: .intptr),
                RuntimeABIParameter(name: "otherRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "Sequence"
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
        RuntimeABIFunctionSpec(
            name: "kk_sequence_find",
            parameters: [
                RuntimeABIParameter(name: "seqRaw", type: .intptr),
                RuntimeABIParameter(name: "fnPtr", type: .intptr),
                RuntimeABIParameter(name: "closureRaw", type: .intptr),
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "Sequence"
        ),
    ]
}
