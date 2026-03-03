// swiftlint:disable identifier_name trailing_comma

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
    ]

    static let kk_sequence_from_list = ExternDecl(
        name: "kk_sequence_from_list",
        parameterTypes: ["intptr_t"],
        returnType: "intptr_t"
    )

    static let kk_sequence_map = ExternDecl(
        name: "kk_sequence_map",
        parameterTypes: ["intptr_t", "intptr_t"],
        returnType: "intptr_t"
    )

    static let kk_sequence_filter = ExternDecl(
        name: "kk_sequence_filter",
        parameterTypes: ["intptr_t", "intptr_t"],
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
}

// swiftlint:enable identifier_name trailing_comma
