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
        kk_sequence_takeWhile,
        kk_sequence_dropWhile,
        kk_sequence_sorted,
        kk_sequence_sortedBy,
        kk_sequence_sortedDescending,
        kk_sequence_mapNotNull,
        kk_sequence_filterNotNull,
        kk_sequence_mapIndexed,
        kk_sequence_withIndex,
        kk_sequence_joinToString,
        kk_sequence_sumOf,
        kk_sequence_associate,
        kk_sequence_associateBy,
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
        parameterTypes: ["intptr_t"],
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

    // STDLIB-270: takeWhile / dropWhile
    static let kk_sequence_takeWhile = ExternDecl(
        name: "kk_sequence_takeWhile",
        parameterTypes: ["intptr_t", "intptr_t", "intptr_t"],
        returnType: "intptr_t"
    )

    static let kk_sequence_dropWhile = ExternDecl(
        name: "kk_sequence_dropWhile",
        parameterTypes: ["intptr_t", "intptr_t", "intptr_t"],
        returnType: "intptr_t"
    )

    // STDLIB-272: Sorting operations
    static let kk_sequence_sorted = ExternDecl(
        name: "kk_sequence_sorted",
        parameterTypes: ["intptr_t"],
        returnType: "intptr_t"
    )

    static let kk_sequence_sortedBy = ExternDecl(
        name: "kk_sequence_sortedBy",
        parameterTypes: ["intptr_t", "intptr_t", "intptr_t", "intptr_t * _Nullable"],
        returnType: "intptr_t"
    )

    static let kk_sequence_sortedDescending = ExternDecl(
        name: "kk_sequence_sortedDescending",
        parameterTypes: ["intptr_t"],
        returnType: "intptr_t"
    )

    // STDLIB-271: Higher-order operations (mapNotNull, filterNotNull, mapIndexed, withIndex)
    static let kk_sequence_mapNotNull = ExternDecl(
        name: "kk_sequence_mapNotNull",
        parameterTypes: ["intptr_t", "intptr_t", "intptr_t", "intptr_t * _Nullable"],
        returnType: "intptr_t"
    )

    static let kk_sequence_filterNotNull = ExternDecl(
        name: "kk_sequence_filterNotNull",
        parameterTypes: ["intptr_t"],
        returnType: "intptr_t"
    )

    static let kk_sequence_mapIndexed = ExternDecl(
        name: "kk_sequence_mapIndexed",
        parameterTypes: ["intptr_t", "intptr_t", "intptr_t", "intptr_t * _Nullable"],
        returnType: "intptr_t"
    )

    static let kk_sequence_withIndex = ExternDecl(
        name: "kk_sequence_withIndex",
        parameterTypes: ["intptr_t"],
        returnType: "intptr_t"
    )

    // STDLIB-275: joinToString, sumOf, associate, associateBy
    static let kk_sequence_joinToString = ExternDecl(
        name: "kk_sequence_joinToString",
        parameterTypes: ["intptr_t", "intptr_t", "intptr_t", "intptr_t"],
        returnType: "intptr_t"
    )

    static let kk_sequence_sumOf = ExternDecl(
        name: "kk_sequence_sumOf",
        parameterTypes: ["intptr_t", "intptr_t", "intptr_t", "intptr_t * _Nullable"],
        returnType: "intptr_t"
    )

    static let kk_sequence_associate = ExternDecl(
        name: "kk_sequence_associate",
        parameterTypes: ["intptr_t", "intptr_t", "intptr_t", "intptr_t * _Nullable"],
        returnType: "intptr_t"
    )

    static let kk_sequence_associateBy = ExternDecl(
        name: "kk_sequence_associateBy",
        parameterTypes: ["intptr_t", "intptr_t", "intptr_t", "intptr_t * _Nullable"],
        returnType: "intptr_t"
    )
}
