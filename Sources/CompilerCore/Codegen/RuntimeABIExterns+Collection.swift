// swiftlint:disable identifier_name

// MARK: - Collection Extern Declarations (STDLIB-001)

public extension RuntimeABIExterns {
    static let collectionExterns: [ExternDecl] = [
        kk_list_of,
        kk_list_size,
        kk_list_get,
        kk_list_contains,
        kk_list_is_empty,
        kk_list_iterator,
        kk_list_iterator_hasNext,
        kk_list_iterator_next,
        kk_list_to_string,
        kk_map_of,
        kk_map_size,
        kk_map_get,
        kk_map_contains_key,
        kk_map_is_empty,
        kk_map_to_string,
        kk_map_iterator,
        kk_map_iterator_hasNext,
        kk_map_iterator_next,
        kk_array_size,
    ]

    static let kk_list_of = ExternDecl(
        name: "kk_list_of",
        parameterTypes: ["intptr_t", "intptr_t"],
        returnType: "intptr_t"
    )

    static let kk_list_size = ExternDecl(
        name: "kk_list_size",
        parameterTypes: ["intptr_t"],
        returnType: "intptr_t"
    )

    static let kk_list_get = ExternDecl(
        name: "kk_list_get",
        parameterTypes: ["intptr_t", "intptr_t"],
        returnType: "intptr_t"
    )

    static let kk_list_contains = ExternDecl(
        name: "kk_list_contains",
        parameterTypes: ["intptr_t", "intptr_t"],
        returnType: "intptr_t"
    )

    static let kk_list_is_empty = ExternDecl(
        name: "kk_list_is_empty",
        parameterTypes: ["intptr_t"],
        returnType: "intptr_t"
    )

    static let kk_list_iterator = ExternDecl(
        name: "kk_list_iterator",
        parameterTypes: ["intptr_t"],
        returnType: "intptr_t"
    )

    static let kk_list_iterator_hasNext = ExternDecl(
        name: "kk_list_iterator_hasNext",
        parameterTypes: ["intptr_t"],
        returnType: "intptr_t"
    )

    static let kk_list_iterator_next = ExternDecl(
        name: "kk_list_iterator_next",
        parameterTypes: ["intptr_t"],
        returnType: "intptr_t"
    )

    static let kk_list_to_string = ExternDecl(
        name: "kk_list_to_string",
        parameterTypes: ["intptr_t"],
        returnType: "void *"
    )

    static let kk_map_of = ExternDecl(
        name: "kk_map_of",
        parameterTypes: ["intptr_t", "intptr_t", "intptr_t"],
        returnType: "intptr_t"
    )

    static let kk_map_size = ExternDecl(
        name: "kk_map_size",
        parameterTypes: ["intptr_t"],
        returnType: "intptr_t"
    )

    static let kk_map_get = ExternDecl(
        name: "kk_map_get",
        parameterTypes: ["intptr_t", "intptr_t"],
        returnType: "intptr_t"
    )

    static let kk_map_contains_key = ExternDecl(
        name: "kk_map_contains_key",
        parameterTypes: ["intptr_t", "intptr_t"],
        returnType: "intptr_t"
    )

    static let kk_map_is_empty = ExternDecl(
        name: "kk_map_is_empty",
        parameterTypes: ["intptr_t"],
        returnType: "intptr_t"
    )

    static let kk_map_to_string = ExternDecl(
        name: "kk_map_to_string",
        parameterTypes: ["intptr_t"],
        returnType: "void *"
    )

    static let kk_map_iterator = ExternDecl(
        name: "kk_map_iterator",
        parameterTypes: ["intptr_t"],
        returnType: "intptr_t"
    )

    static let kk_map_iterator_hasNext = ExternDecl(
        name: "kk_map_iterator_hasNext",
        parameterTypes: ["intptr_t"],
        returnType: "intptr_t"
    )

    static let kk_map_iterator_next = ExternDecl(
        name: "kk_map_iterator_next",
        parameterTypes: ["intptr_t"],
        returnType: "intptr_t"
    )

    static let kk_array_size = ExternDecl(
        name: "kk_array_size",
        parameterTypes: ["intptr_t"],
        returnType: "intptr_t"
    )
}
