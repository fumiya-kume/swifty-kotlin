// swiftlint:disable identifier_name trailing_comma

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
        kk_list_map,
        kk_list_filter,
        kk_list_flatMap,
        kk_list_forEach,
        kk_list_fold,
        kk_list_reduce,
        kk_list_any,
        kk_list_all,
        kk_list_none,
        kk_list_count,
        kk_list_first,
        kk_list_last,
        kk_list_find,
        kk_list_groupBy,
        kk_list_sortedBy,
        kk_map_of,
        kk_map_size,
        kk_map_get,
        kk_map_contains_key,
        kk_map_is_empty,
        kk_map_to_string,
        kk_map_iterator,
        kk_map_iterator_hasNext,
        kk_map_iterator_next,
        kk_array_of,
        kk_array_size,
        kk_pair_new,
        kk_pair_first,
        kk_pair_second,
        kk_pair_to_string,
        kk_build_string,
        kk_build_list,
        kk_build_map,
        kk_string_builder_append,
        kk_mutable_list_add,
        kk_mutable_map_put,
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

    static let kk_list_map = ExternDecl(
        name: "kk_list_map",
        parameterTypes: ["intptr_t", "intptr_t", "intptr_t", "intptr_t * _Nullable"],
        returnType: "intptr_t"
    )

    static let kk_list_filter = ExternDecl(
        name: "kk_list_filter",
        parameterTypes: ["intptr_t", "intptr_t", "intptr_t", "intptr_t * _Nullable"],
        returnType: "intptr_t"
    )

    static let kk_list_flatMap = ExternDecl(
        name: "kk_list_flatMap",
        parameterTypes: ["intptr_t", "intptr_t", "intptr_t", "intptr_t * _Nullable"],
        returnType: "intptr_t"
    )

    static let kk_list_forEach = ExternDecl(
        name: "kk_list_forEach",
        parameterTypes: ["intptr_t", "intptr_t", "intptr_t", "intptr_t * _Nullable"],
        returnType: "intptr_t"
    )

    static let kk_list_fold = ExternDecl(
        name: "kk_list_fold",
        parameterTypes: ["intptr_t", "intptr_t", "intptr_t", "intptr_t", "intptr_t * _Nullable"],
        returnType: "intptr_t"
    )

    static let kk_list_reduce = ExternDecl(
        name: "kk_list_reduce",
        parameterTypes: ["intptr_t", "intptr_t", "intptr_t", "intptr_t * _Nullable"],
        returnType: "intptr_t"
    )

    static let kk_list_any = ExternDecl(
        name: "kk_list_any",
        parameterTypes: ["intptr_t", "intptr_t", "intptr_t", "intptr_t * _Nullable"],
        returnType: "intptr_t"
    )

    static let kk_list_all = ExternDecl(
        name: "kk_list_all",
        parameterTypes: ["intptr_t", "intptr_t", "intptr_t", "intptr_t * _Nullable"],
        returnType: "intptr_t"
    )

    static let kk_list_none = ExternDecl(
        name: "kk_list_none",
        parameterTypes: ["intptr_t", "intptr_t", "intptr_t", "intptr_t * _Nullable"],
        returnType: "intptr_t"
    )

    static let kk_list_count = ExternDecl(
        name: "kk_list_count",
        parameterTypes: ["intptr_t", "intptr_t", "intptr_t", "intptr_t * _Nullable"],
        returnType: "intptr_t"
    )

    static let kk_list_first = ExternDecl(
        name: "kk_list_first",
        parameterTypes: ["intptr_t", "intptr_t", "intptr_t", "intptr_t * _Nullable"],
        returnType: "intptr_t"
    )

    static let kk_list_last = ExternDecl(
        name: "kk_list_last",
        parameterTypes: ["intptr_t", "intptr_t", "intptr_t", "intptr_t * _Nullable"],
        returnType: "intptr_t"
    )

    static let kk_list_find = ExternDecl(
        name: "kk_list_find",
        parameterTypes: ["intptr_t", "intptr_t", "intptr_t", "intptr_t * _Nullable"],
        returnType: "intptr_t"
    )

    static let kk_list_groupBy = ExternDecl(
        name: "kk_list_groupBy",
        parameterTypes: ["intptr_t", "intptr_t", "intptr_t", "intptr_t * _Nullable"],
        returnType: "intptr_t"
    )

    static let kk_list_sortedBy = ExternDecl(
        name: "kk_list_sortedBy",
        parameterTypes: ["intptr_t", "intptr_t", "intptr_t", "intptr_t * _Nullable"],
        returnType: "intptr_t"
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

    static let kk_array_of = ExternDecl(
        name: "kk_array_of",
        parameterTypes: ["intptr_t", "intptr_t"],
        returnType: "intptr_t"
    )

    static let kk_array_size = ExternDecl(
        name: "kk_array_size",
        parameterTypes: ["intptr_t"],
        returnType: "intptr_t"
    )

    /// Pair (FUNC-002)
    static let kk_pair_new = ExternDecl(
        name: "kk_pair_new",
        parameterTypes: ["intptr_t", "intptr_t"],
        returnType: "intptr_t"
    )

    static let kk_pair_first = ExternDecl(
        name: "kk_pair_first",
        parameterTypes: ["intptr_t"],
        returnType: "intptr_t"
    )

    static let kk_pair_second = ExternDecl(
        name: "kk_pair_second",
        parameterTypes: ["intptr_t"],
        returnType: "intptr_t"
    )

    static let kk_pair_to_string = ExternDecl(
        name: "kk_pair_to_string",
        parameterTypes: ["intptr_t"],
        returnType: "void *"
    )

    /// Builder DSL (STDLIB-002)
    static let kk_build_string = ExternDecl(
        name: "kk_build_string",
        parameterTypes: ["intptr_t", "intptr_t * _Nullable"],
        returnType: "intptr_t"
    )

    static let kk_build_list = ExternDecl(
        name: "kk_build_list",
        parameterTypes: ["intptr_t", "intptr_t * _Nullable"],
        returnType: "intptr_t"
    )

    static let kk_build_map = ExternDecl(
        name: "kk_build_map",
        parameterTypes: ["intptr_t", "intptr_t * _Nullable"],
        returnType: "intptr_t"
    )

    static let kk_string_builder_append = ExternDecl(
        name: "kk_string_builder_append",
        parameterTypes: ["intptr_t"],
        returnType: "intptr_t"
    )

    static let kk_mutable_list_add = ExternDecl(
        name: "kk_mutable_list_add",
        parameterTypes: ["intptr_t"],
        returnType: "intptr_t"
    )

    static let kk_mutable_map_put = ExternDecl(
        name: "kk_mutable_map_put",
        parameterTypes: ["intptr_t", "intptr_t"],
        returnType: "intptr_t"
    )
}

// swiftlint:enable identifier_name trailing_comma
