public extension RuntimeABIExterns {
    static let collectionExterns: [ExternDecl] = [
        kk_list_of,
        kk_list_size,
        kk_list_get,
        kk_list_component1,
        kk_list_component2,
        kk_list_component3,
        kk_list_component4,
        kk_list_component5,
        kk_list_contains,
        kk_list_is_empty,
        kk_list_iterator,
        kk_list_iterator_hasNext,
        kk_list_iterator_next,
        kk_list_to_string,
        kk_list_to_mutable_list,
        kk_list_joinToString,
        kk_list_to_set,
        kk_set_of,
        kk_set_size,
        kk_set_contains,
        kk_set_is_empty,
        kk_set_to_string,
        kk_list_map,
        kk_list_filter,
        kk_list_mapNotNull,
        kk_list_forEach,
        kk_list_flatMap,
        kk_list_any,
        kk_list_none,
        kk_list_all,
        kk_list_filterNotNull,
        kk_list_fold,
        kk_list_reduce,
        kk_list_groupBy,
        kk_list_sortedBy,
        kk_list_count,
        kk_list_first,
        kk_list_last,
        kk_list_find,
        kk_list_associateBy,
        kk_list_associateWith,
        kk_list_associate,
        kk_list_zip,
        kk_list_unzip,
        kk_list_withIndex,
        kk_list_forEachIndexed,
        kk_list_mapIndexed,
        kk_list_sumOf,
        kk_list_maxOrNull,
        kk_list_minOrNull,
        kk_list_take,
        kk_list_drop,
        kk_list_reversed,
        kk_list_sorted,
        kk_list_distinct,
        kk_list_shuffled,
        kk_list_random,
        kk_list_randomOrNull,
        kk_list_flatten,
        kk_list_indexOf,
        kk_list_lastIndexOf,
        kk_list_indexOfFirst,
        kk_list_indexOfLast,
        kk_list_filterIsInstance,
        kk_list_chunked,
        kk_list_windowed,
        kk_list_sortedDescending,
        kk_list_sortedByDescending,
        kk_list_sortedWith,
        kk_list_partition,
        kk_map_of,
        kk_map_size,
        kk_map_get,
        kk_map_contains_key,
        kk_map_is_empty,
        kk_map_forEach,
        kk_map_map,
        kk_map_filter,
        kk_map_getOrDefault,
        kk_map_getOrElse,
        kk_map_mapValues,
        kk_map_mapKeys,
        kk_map_keys,
        kk_map_values,
        kk_map_entries,
        kk_map_to_string,
        kk_map_toList,
        kk_map_to_mutable_map,
        kk_map_iterator,
        kk_map_iterator_hasNext,
        kk_map_iterator_next,
        kk_array_of,
        kk_array_size,
        kk_array_toList,
        kk_array_toMutableList,
        kk_list_toTypedArray,
        kk_array_map,
        kk_array_filter,
        kk_array_forEach,
        kk_array_any,
        kk_array_none,
        kk_array_copyOf,
        kk_array_copyOfRange,
        kk_array_fill,
        kk_pair_new,
        kk_pair_first,
        kk_pair_second,
        kk_pair_to_string,
        kk_pair_toList,
        kk_triple_new,
        kk_triple_first,
        kk_triple_second,
        kk_triple_third,
        kk_triple_to_string,
        kk_triple_toList,
        kk_build_string,
        kk_build_list,
        kk_build_list_with_capacity,
        kk_build_map,
        kk_string_builder_append,
        kk_builder_list_add,
        kk_mutable_list_add,
        kk_mutable_list_removeAt,
        kk_mutable_list_clear,
        kk_mutable_list_sort,
        kk_mutable_list_sortBy,
        kk_mutable_list_sortByDescending,
        kk_mutable_set_add,
        kk_mutable_set_remove,
        kk_builder_map_put,
        kk_mutable_map_put,
        kk_mutable_map_remove,
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

    static let kk_list_component1 = ExternDecl(
        name: "kk_list_component1",
        parameterTypes: ["intptr_t"],
        returnType: "intptr_t"
    )
    static let kk_list_component2 = ExternDecl(
        name: "kk_list_component2",
        parameterTypes: ["intptr_t"],
        returnType: "intptr_t"
    )
    static let kk_list_component3 = ExternDecl(
        name: "kk_list_component3",
        parameterTypes: ["intptr_t"],
        returnType: "intptr_t"
    )
    static let kk_list_component4 = ExternDecl(
        name: "kk_list_component4",
        parameterTypes: ["intptr_t"],
        returnType: "intptr_t"
    )
    static let kk_list_component5 = ExternDecl(
        name: "kk_list_component5",
        parameterTypes: ["intptr_t"],
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

    static let kk_list_to_mutable_list = ExternDecl(
        name: "kk_list_to_mutable_list",
        parameterTypes: ["intptr_t"],
        returnType: "intptr_t"
    )

    static let kk_list_joinToString = ExternDecl(
        name: "kk_list_joinToString",
        parameterTypes: ["intptr_t", "intptr_t", "intptr_t", "intptr_t"],
        returnType: "void *"
    )

    static let kk_list_to_set = ExternDecl(
        name: "kk_list_to_set",
        parameterTypes: ["intptr_t"],
        returnType: "intptr_t"
    )

    static let kk_set_of = ExternDecl(
        name: "kk_set_of",
        parameterTypes: ["intptr_t", "intptr_t"],
        returnType: "intptr_t"
    )

    static let kk_set_size = ExternDecl(
        name: "kk_set_size",
        parameterTypes: ["intptr_t"],
        returnType: "intptr_t"
    )

    static let kk_set_contains = ExternDecl(
        name: "kk_set_contains",
        parameterTypes: ["intptr_t", "intptr_t"],
        returnType: "intptr_t"
    )

    static let kk_set_is_empty = ExternDecl(
        name: "kk_set_is_empty",
        parameterTypes: ["intptr_t"],
        returnType: "intptr_t"
    )

    static let kk_set_to_string = ExternDecl(
        name: "kk_set_to_string",
        parameterTypes: ["intptr_t"],
        returnType: "void *"
    )

    static let kk_list_associateBy = ExternDecl(
        name: "kk_list_associateBy",
        parameterTypes: ["intptr_t", "intptr_t", "intptr_t", "intptr_t * _Nullable"],
        returnType: "intptr_t"
    )

    static let kk_list_associateWith = ExternDecl(
        name: "kk_list_associateWith",
        parameterTypes: ["intptr_t", "intptr_t", "intptr_t", "intptr_t * _Nullable"],
        returnType: "intptr_t"
    )

    static let kk_list_associate = ExternDecl(
        name: "kk_list_associate",
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

    static let kk_map_forEach = ExternDecl(
        name: "kk_map_forEach",
        parameterTypes: ["intptr_t", "intptr_t", "intptr_t", "intptr_t * _Nullable"],
        returnType: "intptr_t"
    )

    static let kk_map_map = ExternDecl(
        name: "kk_map_map",
        parameterTypes: ["intptr_t", "intptr_t", "intptr_t", "intptr_t * _Nullable"],
        returnType: "intptr_t"
    )

    static let kk_map_filter = ExternDecl(
        name: "kk_map_filter",
        parameterTypes: ["intptr_t", "intptr_t", "intptr_t", "intptr_t * _Nullable"],
        returnType: "intptr_t"
    )

    static let kk_map_getOrDefault = ExternDecl(
        name: "kk_map_getOrDefault",
        parameterTypes: ["intptr_t", "intptr_t", "intptr_t"],
        returnType: "intptr_t"
    )

    static let kk_map_getOrElse = ExternDecl(
        name: "kk_map_getOrElse",
        parameterTypes: ["intptr_t", "intptr_t", "intptr_t", "intptr_t", "intptr_t * _Nullable"],
        returnType: "intptr_t"
    )

    static let kk_map_mapValues = ExternDecl(
        name: "kk_map_mapValues",
        parameterTypes: ["intptr_t", "intptr_t", "intptr_t", "intptr_t * _Nullable"],
        returnType: "intptr_t"
    )

    static let kk_map_mapKeys = ExternDecl(
        name: "kk_map_mapKeys",
        parameterTypes: ["intptr_t", "intptr_t", "intptr_t", "intptr_t * _Nullable"],
        returnType: "intptr_t"
    )

    static let kk_map_keys = ExternDecl(
        name: "kk_map_keys",
        parameterTypes: ["intptr_t"],
        returnType: "intptr_t"
    )

    static let kk_map_values = ExternDecl(
        name: "kk_map_values",
        parameterTypes: ["intptr_t"],
        returnType: "intptr_t"
    )

    static let kk_map_entries = ExternDecl(
        name: "kk_map_entries",
        parameterTypes: ["intptr_t"],
        returnType: "intptr_t"
    )

    static let kk_map_to_string = ExternDecl(
        name: "kk_map_to_string",
        parameterTypes: ["intptr_t"],
        returnType: "void *"
    )

    static let kk_map_toList = ExternDecl(
        name: "kk_map_toList",
        parameterTypes: ["intptr_t"],
        returnType: "intptr_t"
    )

    static let kk_map_to_mutable_map = ExternDecl(
        name: "kk_map_to_mutable_map",
        parameterTypes: ["intptr_t"],
        returnType: "intptr_t"
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

    /// Array conversion functions (STDLIB-087)
    static let kk_array_toList = ExternDecl(
        name: "kk_array_toList",
        parameterTypes: ["intptr_t"],
        returnType: "intptr_t"
    )

    static let kk_array_toMutableList = ExternDecl(
        name: "kk_array_toMutableList",
        parameterTypes: ["intptr_t"],
        returnType: "intptr_t"
    )

    static let kk_list_toTypedArray = ExternDecl(
        name: "kk_list_toTypedArray",
        parameterTypes: ["intptr_t"],
        returnType: "intptr_t"
    )

    /// Array higher-order functions (STDLIB-088)
    static let kk_array_map = ExternDecl(
        name: "kk_array_map",
        parameterTypes: ["intptr_t", "intptr_t", "intptr_t", "intptr_t * _Nullable"],
        returnType: "intptr_t"
    )

    static let kk_array_filter = ExternDecl(
        name: "kk_array_filter",
        parameterTypes: ["intptr_t", "intptr_t", "intptr_t", "intptr_t * _Nullable"],
        returnType: "intptr_t"
    )

    static let kk_array_forEach = ExternDecl(
        name: "kk_array_forEach",
        parameterTypes: ["intptr_t", "intptr_t", "intptr_t", "intptr_t * _Nullable"],
        returnType: "intptr_t"
    )

    static let kk_array_any = ExternDecl(
        name: "kk_array_any",
        parameterTypes: ["intptr_t", "intptr_t", "intptr_t", "intptr_t * _Nullable"],
        returnType: "intptr_t"
    )

    static let kk_array_none = ExternDecl(
        name: "kk_array_none",
        parameterTypes: ["intptr_t", "intptr_t", "intptr_t", "intptr_t * _Nullable"],
        returnType: "intptr_t"
    )

    /// Array utility functions (STDLIB-089)
    static let kk_array_copyOf = ExternDecl(
        name: "kk_array_copyOf",
        parameterTypes: ["intptr_t"],
        returnType: "intptr_t"
    )

    static let kk_array_copyOfRange = ExternDecl(
        name: "kk_array_copyOfRange",
        parameterTypes: ["intptr_t", "intptr_t", "intptr_t"],
        returnType: "intptr_t"
    )

    static let kk_array_fill = ExternDecl(
        name: "kk_array_fill",
        parameterTypes: ["intptr_t", "intptr_t"],
        returnType: "intptr_t"
    )

    /// Higher-order collection functions (STDLIB-005)
    /// Runtime signature: (listRaw, fnPtr, closureRaw, outThrown)
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

    static let kk_list_mapNotNull = ExternDecl(
        name: "kk_list_mapNotNull",
        parameterTypes: ["intptr_t", "intptr_t", "intptr_t", "intptr_t * _Nullable"],
        returnType: "intptr_t"
    )

    static let kk_list_filterNotNull = ExternDecl(
        name: "kk_list_filterNotNull",
        parameterTypes: ["intptr_t"],
        returnType: "intptr_t"
    )

    static let kk_list_forEach = ExternDecl(
        name: "kk_list_forEach",
        parameterTypes: ["intptr_t", "intptr_t", "intptr_t", "intptr_t * _Nullable"],
        returnType: "intptr_t"
    )

    static let kk_list_flatMap = ExternDecl(
        name: "kk_list_flatMap",
        parameterTypes: ["intptr_t", "intptr_t", "intptr_t", "intptr_t * _Nullable"],
        returnType: "intptr_t"
    )

    static let kk_list_any = ExternDecl(
        name: "kk_list_any",
        parameterTypes: ["intptr_t", "intptr_t", "intptr_t", "intptr_t * _Nullable"],
        returnType: "intptr_t"
    )

    static let kk_list_none = ExternDecl(
        name: "kk_list_none",
        parameterTypes: ["intptr_t", "intptr_t", "intptr_t", "intptr_t * _Nullable"],
        returnType: "intptr_t"
    )

    static let kk_list_all = ExternDecl(
        name: "kk_list_all",
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

    static let kk_list_zip = ExternDecl(
        name: "kk_list_zip",
        parameterTypes: ["intptr_t", "intptr_t"],
        returnType: "intptr_t"
    )

    static let kk_list_unzip = ExternDecl(
        name: "kk_list_unzip",
        parameterTypes: ["intptr_t"],
        returnType: "intptr_t"
    )

    static let kk_list_withIndex = ExternDecl(
        name: "kk_list_withIndex",
        parameterTypes: ["intptr_t"],
        returnType: "intptr_t"
    )

    static let kk_list_forEachIndexed = ExternDecl(
        name: "kk_list_forEachIndexed",
        parameterTypes: ["intptr_t", "intptr_t", "intptr_t", "intptr_t * _Nullable"],
        returnType: "intptr_t"
    )

    static let kk_list_mapIndexed = ExternDecl(
        name: "kk_list_mapIndexed",
        parameterTypes: ["intptr_t", "intptr_t", "intptr_t", "intptr_t * _Nullable"],
        returnType: "intptr_t"
    )

    static let kk_list_sumOf = ExternDecl(
        name: "kk_list_sumOf",
        parameterTypes: ["intptr_t", "intptr_t", "intptr_t", "intptr_t * _Nullable"],
        returnType: "intptr_t"
    )

    static let kk_list_maxOrNull = ExternDecl(
        name: "kk_list_maxOrNull",
        parameterTypes: ["intptr_t"],
        returnType: "intptr_t"
    )

    static let kk_list_minOrNull = ExternDecl(
        name: "kk_list_minOrNull",
        parameterTypes: ["intptr_t"],
        returnType: "intptr_t"
    )

    static let kk_list_take = ExternDecl(
        name: "kk_list_take",
        parameterTypes: ["intptr_t", "intptr_t"],
        returnType: "intptr_t"
    )

    static let kk_list_drop = ExternDecl(
        name: "kk_list_drop",
        parameterTypes: ["intptr_t", "intptr_t"],
        returnType: "intptr_t"
    )

    static let kk_list_reversed = ExternDecl(
        name: "kk_list_reversed",
        parameterTypes: ["intptr_t"],
        returnType: "intptr_t"
    )

    static let kk_list_sorted = ExternDecl(
        name: "kk_list_sorted",
        parameterTypes: ["intptr_t"],
        returnType: "intptr_t"
    )

    static let kk_list_distinct = ExternDecl(
        name: "kk_list_distinct",
        parameterTypes: ["intptr_t"],
        returnType: "intptr_t"
    )

    static let kk_list_shuffled = ExternDecl(
        name: "kk_list_shuffled",
        parameterTypes: ["intptr_t"],
        returnType: "intptr_t"
    )

    static let kk_list_random = ExternDecl(
        name: "kk_list_random",
        parameterTypes: ["intptr_t", "intptr_t * _Nullable"],
        returnType: "intptr_t"
    )

    static let kk_list_randomOrNull = ExternDecl(
        name: "kk_list_randomOrNull",
        parameterTypes: ["intptr_t"],
        returnType: "intptr_t"
    )

    static let kk_list_flatten = ExternDecl(
        name: "kk_list_flatten",
        parameterTypes: ["intptr_t"],
        returnType: "intptr_t"
    )

    static let kk_list_indexOf = ExternDecl(
        name: "kk_list_indexOf",
        parameterTypes: ["intptr_t", "intptr_t"],
        returnType: "intptr_t"
    )

    static let kk_list_lastIndexOf = ExternDecl(
        name: "kk_list_lastIndexOf",
        parameterTypes: ["intptr_t", "intptr_t"],
        returnType: "intptr_t"
    )

    static let kk_list_indexOfFirst = ExternDecl(
        name: "kk_list_indexOfFirst",
        parameterTypes: ["intptr_t", "intptr_t", "intptr_t", "intptr_t * _Nullable"],
        returnType: "intptr_t"
    )

    static let kk_list_indexOfLast = ExternDecl(
        name: "kk_list_indexOfLast",
        parameterTypes: ["intptr_t", "intptr_t", "intptr_t", "intptr_t * _Nullable"],
        returnType: "intptr_t"
    )

    static let kk_list_filterIsInstance = ExternDecl(
        name: "kk_list_filterIsInstance",
        parameterTypes: ["intptr_t", "intptr_t"],
        returnType: "intptr_t"
    )

    static let kk_list_chunked = ExternDecl(
        name: "kk_list_chunked",
        parameterTypes: ["intptr_t", "intptr_t"],
        returnType: "intptr_t"
    )

    static let kk_list_windowed = ExternDecl(
        name: "kk_list_windowed",
        parameterTypes: ["intptr_t", "intptr_t", "intptr_t"],
        returnType: "intptr_t"
    )

    static let kk_list_sortedDescending = ExternDecl(
        name: "kk_list_sortedDescending",
        parameterTypes: ["intptr_t"],
        returnType: "intptr_t"
    )

    static let kk_list_sortedByDescending = ExternDecl(
        name: "kk_list_sortedByDescending",
        parameterTypes: ["intptr_t", "intptr_t", "intptr_t", "intptr_t * _Nullable"],
        returnType: "intptr_t"
    )

    static let kk_list_sortedWith = ExternDecl(
        name: "kk_list_sortedWith",
        parameterTypes: ["intptr_t", "intptr_t", "intptr_t", "intptr_t * _Nullable"],
        returnType: "intptr_t"
    )

    static let kk_list_partition = ExternDecl(
        name: "kk_list_partition",
        parameterTypes: ["intptr_t", "intptr_t", "intptr_t", "intptr_t * _Nullable"],
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

    static let kk_pair_toList = ExternDecl(
        name: "kk_pair_toList",
        parameterTypes: ["intptr_t"],
        returnType: "intptr_t"
    )

    /// Triple (STDLIB-120)
    static let kk_triple_new = ExternDecl(
        name: "kk_triple_new",
        parameterTypes: ["intptr_t", "intptr_t", "intptr_t"],
        returnType: "intptr_t"
    )

    static let kk_triple_first = ExternDecl(
        name: "kk_triple_first",
        parameterTypes: ["intptr_t"],
        returnType: "intptr_t"
    )

    static let kk_triple_second = ExternDecl(
        name: "kk_triple_second",
        parameterTypes: ["intptr_t"],
        returnType: "intptr_t"
    )

    static let kk_triple_third = ExternDecl(
        name: "kk_triple_third",
        parameterTypes: ["intptr_t"],
        returnType: "intptr_t"
    )

    static let kk_triple_to_string = ExternDecl(
        name: "kk_triple_to_string",
        parameterTypes: ["intptr_t"],
        returnType: "void *"
    )

    static let kk_triple_toList = ExternDecl(
        name: "kk_triple_toList",
        parameterTypes: ["intptr_t"],
        returnType: "intptr_t"
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

    static let kk_build_list_with_capacity = ExternDecl(
        name: "kk_build_list_with_capacity",
        parameterTypes: ["intptr_t", "intptr_t", "intptr_t * _Nullable"],
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

    static let kk_builder_list_add = ExternDecl(
        name: "kk_builder_list_add",
        parameterTypes: ["intptr_t"],
        returnType: "intptr_t"
    )

    static let kk_mutable_list_add = ExternDecl(
        name: "kk_mutable_list_add",
        parameterTypes: ["intptr_t", "intptr_t"],
        returnType: "intptr_t"
    )

    static let kk_mutable_list_removeAt = ExternDecl(
        name: "kk_mutable_list_removeAt",
        parameterTypes: ["intptr_t", "intptr_t"],
        returnType: "intptr_t"
    )

    static let kk_mutable_list_clear = ExternDecl(
        name: "kk_mutable_list_clear",
        parameterTypes: ["intptr_t"],
        returnType: "intptr_t"
    )

    static let kk_mutable_list_sort = ExternDecl(
        name: "kk_mutable_list_sort",
        parameterTypes: ["intptr_t"],
        returnType: "intptr_t"
    )

    static let kk_mutable_list_sortBy = ExternDecl(
        name: "kk_mutable_list_sortBy",
        parameterTypes: ["intptr_t", "intptr_t", "intptr_t", "intptr_t * _Nullable"],
        returnType: "intptr_t"
    )

    static let kk_mutable_list_sortByDescending = ExternDecl(
        name: "kk_mutable_list_sortByDescending",
        parameterTypes: ["intptr_t", "intptr_t", "intptr_t", "intptr_t * _Nullable"],
        returnType: "intptr_t"
    )

    static let kk_mutable_set_add = ExternDecl(
        name: "kk_mutable_set_add",
        parameterTypes: ["intptr_t", "intptr_t"],
        returnType: "intptr_t"
    )

    static let kk_mutable_set_remove = ExternDecl(
        name: "kk_mutable_set_remove",
        parameterTypes: ["intptr_t", "intptr_t"],
        returnType: "intptr_t"
    )

    static let kk_builder_map_put = ExternDecl(
        name: "kk_builder_map_put",
        parameterTypes: ["intptr_t", "intptr_t"],
        returnType: "intptr_t"
    )

    static let kk_mutable_map_put = ExternDecl(
        name: "kk_mutable_map_put",
        parameterTypes: ["intptr_t", "intptr_t", "intptr_t"],
        returnType: "intptr_t"
    )

    static let kk_mutable_map_remove = ExternDecl(
        name: "kk_mutable_map_remove",
        parameterTypes: ["intptr_t", "intptr_t"],
        returnType: "intptr_t"
    )
}
