// MARK: - Sequence Extern Declarations (STDLIB-003)

public extension RuntimeABIExterns {
    static let sequenceExterns: [ExternDecl] = [
        kk_sequence_from_list,
        kk_sequence_map,
        kk_sequence_filter,
        kk_sequence_take,
        kk_sequence_to_list,
        kk_sequence_builder_create,
        kk_sequence_builder_yield,
        kk_sequence_builder_build,
        kk_sequence_of,
        kk_sequence_generate,
        kk_sequence_forEach,
        kk_sequence_flatMap,
        kk_sequence_drop,
        kk_sequence_distinct,
        kk_sequence_zip,
    ]

    static let kk_sequence_from_list = ExternDecl(
        name: "kk_sequence_from_list",
        parameterTypes: ["intptr_t"],
        returnType: "intptr_t"
    )

    static let kk_sequence_map = ExternDecl(
        name: "kk_sequence_map",
        parameterTypes: ["intptr_t", "intptr_t", "intptr_t"],
        returnType: "intptr_t"
    )

    static let kk_sequence_filter = ExternDecl(
        name: "kk_sequence_filter",
        parameterTypes: ["intptr_t", "intptr_t", "intptr_t"],
        returnType: "intptr_t"
    )

    static let kk_sequence_take = ExternDecl(
        name: "kk_sequence_take",
        parameterTypes: ["intptr_t", "intptr_t"],
        returnType: "intptr_t"
    )

    static let kk_sequence_to_list = ExternDecl(
        name: "kk_sequence_to_list",
        parameterTypes: ["intptr_t"],
        returnType: "intptr_t"
    )

    static let kk_sequence_builder_create = ExternDecl(
        name: "kk_sequence_builder_create",
        parameterTypes: [],
        returnType: "intptr_t"
    )

    static let kk_sequence_builder_yield = ExternDecl(
        name: "kk_sequence_builder_yield",
        parameterTypes: ["intptr_t", "intptr_t"],
        returnType: "intptr_t"
    )

    static let kk_sequence_builder_build = ExternDecl(
        name: "kk_sequence_builder_build",
        parameterTypes: ["intptr_t"],
        returnType: "intptr_t"
    )

    // STDLIB-097: Factory functions
    static let kk_sequence_of = ExternDecl(
        name: "kk_sequence_of",
        parameterTypes: ["intptr_t", "intptr_t"],
        returnType: "intptr_t"
    )

    static let kk_sequence_generate = ExternDecl(
        name: "kk_sequence_generate",
        parameterTypes: ["intptr_t", "intptr_t", "intptr_t"],
        returnType: "intptr_t"
    )

    // STDLIB-095: Terminal operations
    static let kk_sequence_forEach = ExternDecl(
        name: "kk_sequence_forEach",
        parameterTypes: ["intptr_t", "intptr_t", "intptr_t"],
        returnType: "intptr_t"
    )

    static let kk_sequence_flatMap = ExternDecl(
        name: "kk_sequence_flatMap",
        parameterTypes: ["intptr_t", "intptr_t", "intptr_t"],
        returnType: "intptr_t"
    )

    // STDLIB-096: Intermediate operations
    static let kk_sequence_drop = ExternDecl(
        name: "kk_sequence_drop",
        parameterTypes: ["intptr_t", "intptr_t"],
        returnType: "intptr_t"
    )

    static let kk_sequence_distinct = ExternDecl(
        name: "kk_sequence_distinct",
        parameterTypes: ["intptr_t"],
        returnType: "intptr_t"
    )

    static let kk_sequence_zip = ExternDecl(
        name: "kk_sequence_zip",
        parameterTypes: ["intptr_t", "intptr_t"],
        returnType: "intptr_t"
    )
}
