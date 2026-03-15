// Sequence ABI specs (STDLIB-003)

public extension RuntimeABISpec {
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
            name: "kk_sequence_map",
            parameters: [
                RuntimeABIParameter(name: "seqRaw", type: .intptr),
                RuntimeABIParameter(name: "fnPtr", type: .intptr),
                RuntimeABIParameter(name: "closureRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "Sequence"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_sequence_filter",
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
        // Terminal operations
        RuntimeABIFunctionSpec(
            name: "kk_sequence_to_list",
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
        RuntimeABIFunctionSpec(
            name: "kk_sequence_builder_build",
            parameters: [
                RuntimeABIParameter(name: "fnPtr", type: .intptr),
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
            name: "kk_sequence_generate",
            parameters: [
                RuntimeABIParameter(name: "seed", type: .intptr),
                RuntimeABIParameter(name: "fnPtr", type: .intptr),
                RuntimeABIParameter(name: "closureRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "Sequence"
        ),
        // Terminal operations (STDLIB-095)
        RuntimeABIFunctionSpec(
            name: "kk_sequence_forEach",
            parameters: [
                RuntimeABIParameter(name: "seqRaw", type: .intptr),
                RuntimeABIParameter(name: "fnPtr", type: .intptr),
                RuntimeABIParameter(name: "closureRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "Sequence"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_sequence_flatMap",
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
        // Higher-order operations (STDLIB-271)
        RuntimeABIFunctionSpec(
            name: "kk_sequence_mapNotNull",
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
            name: "kk_sequence_mapIndexed",
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
        // STDLIB-275: joinToString, sumOf, associate, associateBy
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
            name: "kk_sequence_sumOf",
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
            name: "kk_sequence_associate",
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
            name: "kk_sequence_associateBy",
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
