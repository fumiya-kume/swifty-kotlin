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
            ],
            returnType: .intptr,
            section: "Sequence"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_sequence_filter",
            parameters: [
                RuntimeABIParameter(name: "seqRaw", type: .intptr),
                RuntimeABIParameter(name: "fnPtr", type: .intptr),
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
    ]
}
