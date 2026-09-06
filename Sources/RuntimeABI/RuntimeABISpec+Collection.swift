public extension RuntimeABISpec {
    private static func stdlibMapHOFName(_ memberName: String, arity: Int, fallback: String) -> String {
        StdlibSurfaceSpec.collectionHOFRuntimeLinkName(
            ownerKind: .map,
            memberName: memberName,
            arity: arity,
            fallback: fallback
        )
    }

    static let collectionFunctions: [RuntimeABIFunctionSpec] = [
        // Core helpers
        RuntimeABIFunctionSpec(
            name: "__kk_values_equal",
            parameters: [
                RuntimeABIParameter(name: "lhs", type: .intptr),
                RuntimeABIParameter(name: "rhs", type: .intptr),
            ],
            returnType: .intptr,
            section: "Collection",
            isThrowing: false
        ),
        // List
        RuntimeABIFunctionSpec(
            name: "__kk_list_of",
            parameters: [
                RuntimeABIParameter(name: "arrayRaw", type: .intptr),
                RuntimeABIParameter(name: "count", type: .intptr),
            ],
            returnType: .intptr,
            section: "Collection",
            isThrowing: false
        ),
        // STDLIB-410: emptyList
        RuntimeABIFunctionSpec(
            name: "__kk_emptyList",
            parameters: [],
            returnType: .intptr,
            section: "Collection"
        ),
        RuntimeABIFunctionSpec(
            name: "__kk_list_size",
            parameters: [
                RuntimeABIParameter(name: "listRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "Collection",
            isThrowing: false
        ),
        RuntimeABIFunctionSpec(
            name: "__kk_list_get",
            parameters: [
                RuntimeABIParameter(name: "listRaw", type: .intptr),
                RuntimeABIParameter(name: "index", type: .intptr),
            ],
            returnType: .intptr,
            section: "Collection",
            isThrowing: false
        ),
        RuntimeABIFunctionSpec(
            name: "__kk_enum_entries_get",
            parameters: [
                RuntimeABIParameter(name: "listRaw", type: .intptr),
                RuntimeABIParameter(name: "index", type: .intptr),
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "Enum",
            isThrowing: true
        ),
    ]
    + [
        RuntimeABIFunctionSpec(
            name: "kk_list_is_empty",
            parameters: [
                RuntimeABIParameter(name: "listRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "Collection",
            isThrowing: false
        ),
        RuntimeABIFunctionSpec(
            name: "kk_list_iterator",
            parameters: [
                RuntimeABIParameter(name: "listRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "Collection",
            isThrowing: false
        ),
        RuntimeABIFunctionSpec(
            name: "kk_list_iterator_hasNext",
            parameters: [
                RuntimeABIParameter(name: "iterRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "Collection",
            isThrowing: false
        ),
        RuntimeABIFunctionSpec(
            name: "kk_list_iterator_next",
            parameters: [
                RuntimeABIParameter(name: "iterRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "Collection",
            isThrowing: false
        ),
        // IndexingIterable is the iterator bridge retained by List.withIndex().
        RuntimeABIFunctionSpec(
            name: "kk_indexing_iterable_iterator",
            parameters: [
                RuntimeABIParameter(name: "iterableRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "Collection",
            isThrowing: false
        ),
        RuntimeABIFunctionSpec(
            name: "kk_indexing_iterable_hasNext",
            parameters: [
                RuntimeABIParameter(name: "iterRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "Collection",
            isThrowing: false
        ),
        RuntimeABIFunctionSpec(
            name: "kk_indexing_iterable_next",
            parameters: [
                RuntimeABIParameter(name: "iterRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "Collection",
            isThrowing: false
        ),
        RuntimeABIFunctionSpec(
            name: "kk_list_iterator_at",
            parameters: [
                RuntimeABIParameter(name: "listRaw", type: .intptr),
                RuntimeABIParameter(name: "index", type: .intptr),
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "Collection"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_list_iterator_hasPrevious",
            parameters: [
                RuntimeABIParameter(name: "iterRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "Collection"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_list_iterator_previous",
            parameters: [
                RuntimeABIParameter(name: "iterRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "Collection"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_list_iterator_nextIndex",
            parameters: [
                RuntimeABIParameter(name: "iterRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "Collection",
            isThrowing: false
        ),
        RuntimeABIFunctionSpec(
            name: "kk_list_iterator_previousIndex",
            parameters: [
                RuntimeABIParameter(name: "iterRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "Collection",
            isThrowing: false
        ),
        RuntimeABIFunctionSpec(
            name: "kk_list_to_string",
            parameters: [
                RuntimeABIParameter(name: "listRaw", type: .intptr),
            ],
            returnType: .opaquePointer,
            section: "Collection",
            isThrowing: false
        ),
        // Set
        RuntimeABIFunctionSpec(
            name: "__kk_set_of",
            parameters: [
                RuntimeABIParameter(name: "arrayRaw", type: .intptr),
                RuntimeABIParameter(name: "count", type: .intptr),
            ],
            returnType: .intptr,
            section: "Collection",
            isThrowing: false
        ),
        RuntimeABIFunctionSpec(
            name: "__kk_hash_set_of",
            parameters: [
                RuntimeABIParameter(name: "arrayRaw", type: .intptr),
                RuntimeABIParameter(name: "count", type: .intptr),
            ],
            returnType: .intptr,
            section: "Collection",
            isThrowing: false
        ),
        // STDLIB-410: emptySet
        RuntimeABIFunctionSpec(
            name: "__kk_emptySet",
            parameters: [],
            returnType: .intptr,
            section: "Collection"
        ),
        // BUG-196: Attach runtime-backed storage to source-allocated
        // LinkedHashSet instances, including user subclasses.
        RuntimeABIFunctionSpec(
            name: "__kk_linked_hash_set_init",
            parameters: [
                RuntimeABIParameter(name: "setRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "Collection",
            isThrowing: false
        ),
        RuntimeABIFunctionSpec(
            name: "__kk_set_size",
            parameters: [
                RuntimeABIParameter(name: "setRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "Collection",
            isThrowing: false
        ),
        RuntimeABIFunctionSpec(
            name: "__kk_set_contains",
            parameters: [
                RuntimeABIParameter(name: "setRaw", type: .intptr),
                RuntimeABIParameter(name: "element", type: .intptr),
            ],
            returnType: .intptr,
            section: "Collection",
            isThrowing: false
        ),
        RuntimeABIFunctionSpec(
            name: "__kk_set_is_empty",
            parameters: [
                RuntimeABIParameter(name: "setRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "Collection",
            isThrowing: false
        ),
        RuntimeABIFunctionSpec(
            name: "__kk_set_to_string",
            parameters: [
                RuntimeABIParameter(name: "setRaw", type: .intptr),
            ],
            returnType: .opaquePointer,
            section: "Collection",
            isThrowing: false
        ),
        RuntimeABIFunctionSpec(
            name: "__kk_collection_toList",
            parameters: [
                RuntimeABIParameter(name: "collRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "Collection"
        ),
        // STDLIB-021: Collection<T>.toMutableList()
        RuntimeABIFunctionSpec(
            name: "__kk_collection_toMutableList",
            parameters: [
                RuntimeABIParameter(name: "collRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "Collection",
            isThrowing: false
        ),
        RuntimeABIFunctionSpec(
            name: "__kk_collection_toTypedArray",
            parameters: [
                RuntimeABIParameter(name: "collRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "Collection"
        ),
        // STDLIB-021: Iterable<T>.toMutableSet()
        RuntimeABIFunctionSpec(
            name: "__kk_iterable_toMutableSet",
            parameters: [
                RuntimeABIParameter(name: "iterableRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "Collection",
            isThrowing: false
        ),
        RuntimeABIFunctionSpec(
            name: "__kk_iterable_toHashSet",
            parameters: [
                RuntimeABIParameter(name: "iterableRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "Collection",
            isThrowing: false
        ),
        RuntimeABIFunctionSpec(
            name: "__kk_collection_toCollection",
            parameters: [
                RuntimeABIParameter(name: "collRaw", type: .intptr),
                RuntimeABIParameter(name: "destRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "Collection",
            isThrowing: false
        ),
        RuntimeABIFunctionSpec(
            name: "__kk_collection_size",
            parameters: [
                RuntimeABIParameter(name: "collRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "Collection",
            isThrowing: false
        ),
        RuntimeABIFunctionSpec(
            name: "__kk_collection_isEmpty",
            parameters: [
                RuntimeABIParameter(name: "collRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "Collection",
            isThrowing: false
        ),
        RuntimeABIFunctionSpec(
            name: "__kk_collection_containsAll",
            parameters: [
                RuntimeABIParameter(name: "collRaw", type: .intptr),
                RuntimeABIParameter(name: "elementsRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "Collection",
            isThrowing: false
        ),
    ] + Self.collectionHOFFunctions + [
        // Map
        RuntimeABIFunctionSpec(
            name: "__kk_map_of",
            parameters: [
                RuntimeABIParameter(name: "keysArrayRaw", type: .intptr),
                RuntimeABIParameter(name: "valuesArrayRaw", type: .intptr),
                RuntimeABIParameter(name: "count", type: .intptr),
            ],
            returnType: .intptr,
            section: "Collection",
            isThrowing: false
        ),
        RuntimeABIFunctionSpec(
            name: "__kk_hash_map_of",
            parameters: [
                RuntimeABIParameter(name: "keysArrayRaw", type: .intptr),
                RuntimeABIParameter(name: "valuesArrayRaw", type: .intptr),
                RuntimeABIParameter(name: "count", type: .intptr),
            ],
            returnType: .intptr,
            section: "Collection",
            isThrowing: false
        ),
        RuntimeABIFunctionSpec(
            name: "__kk_map_of_pairs",
            parameters: [
                RuntimeABIParameter(name: "pairsArrayRaw", type: .intptr),
                RuntimeABIParameter(name: "count", type: .intptr),
            ],
            returnType: .intptr,
            section: "Collection",
            isThrowing: false
        ),
        // STDLIB-410: emptyMap
        RuntimeABIFunctionSpec(
            name: "__kk_emptyMap",
            parameters: [],
            returnType: .intptr,
            section: "Collection"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_map_size",
            parameters: [
                RuntimeABIParameter(name: "mapRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "Collection",
            isThrowing: false
        ),
        RuntimeABIFunctionSpec(
            name: "__kk_map_get",
            parameters: [
                RuntimeABIParameter(name: "mapRaw", type: .intptr),
                RuntimeABIParameter(name: "key", type: .intptr),
            ],
            returnType: .intptr,
            section: "Collection",
            isThrowing: false
        ),
        RuntimeABIFunctionSpec(
            name: "kk_map_is_empty",
            parameters: [
                RuntimeABIParameter(name: "mapRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "Collection",
            isThrowing: false
        ),
        RuntimeABIFunctionSpec(
            name: stdlibMapHOFName("forEach", arity: 1, fallback: "kk_map_forEach"),
            parameters: [
                RuntimeABIParameter(name: "mapRaw", type: .intptr),
                RuntimeABIParameter(name: "fnPtr", type: .intptr),
                RuntimeABIParameter(name: "closureRaw", type: .intptr),
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "Collection"
        ),
        RuntimeABIFunctionSpec(
            name: stdlibMapHOFName("map", arity: 1, fallback: "kk_map_map"),
            parameters: [
                RuntimeABIParameter(name: "mapRaw", type: .intptr),
                RuntimeABIParameter(name: "fnPtr", type: .intptr),
                RuntimeABIParameter(name: "closureRaw", type: .intptr),
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "Collection"
        ),
        RuntimeABIFunctionSpec(
            name: stdlibMapHOFName("mapNotNull", arity: 1, fallback: "kk_map_mapNotNull"),
            parameters: [
                RuntimeABIParameter(name: "mapRaw", type: .intptr),
                RuntimeABIParameter(name: "fnPtr", type: .intptr),
                RuntimeABIParameter(name: "closureRaw", type: .intptr),
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "Collection"
        ),
        RuntimeABIFunctionSpec(
            name: stdlibMapHOFName("filter", arity: 1, fallback: "kk_map_filter"),
            parameters: [
                RuntimeABIParameter(name: "mapRaw", type: .intptr),
                RuntimeABIParameter(name: "fnPtr", type: .intptr),
                RuntimeABIParameter(name: "closureRaw", type: .intptr),
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "Collection"
        ),
        RuntimeABIFunctionSpec(
            name: stdlibMapHOFName("filterNot", arity: 1, fallback: "kk_map_filterNot"),
            parameters: [
                RuntimeABIParameter(name: "mapRaw", type: .intptr),
                RuntimeABIParameter(name: "fnPtr", type: .intptr),
                RuntimeABIParameter(name: "closureRaw", type: .intptr),
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "Collection"
        ),
        RuntimeABIFunctionSpec(
            name: "__kk_map_withDefault",
            parameters: [
                RuntimeABIParameter(name: "mapRaw", type: .intptr),
                RuntimeABIParameter(name: "fnPtr", type: .intptr),
                RuntimeABIParameter(name: "closureRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "Collection",
            isThrowing: false
        ),
        RuntimeABIFunctionSpec(
            name: "__kk_map_implicit_default",
            parameters: [
                RuntimeABIParameter(name: "mapRaw", type: .intptr),
                RuntimeABIParameter(name: "key", type: .intptr),
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "Collection"
        ),
        RuntimeABIFunctionSpec(
            name: "__kk_map_has_default",
            parameters: [
                RuntimeABIParameter(name: "mapRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "Collection",
            isThrowing: false
        ),
        RuntimeABIFunctionSpec(
            name: stdlibMapHOFName("filterKeys", arity: 1, fallback: "kk_map_filterKeys"),
            parameters: [
                RuntimeABIParameter(name: "mapRaw", type: .intptr),
                RuntimeABIParameter(name: "fnPtr", type: .intptr),
                RuntimeABIParameter(name: "closureRaw", type: .intptr),
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "Collection"
        ),
        RuntimeABIFunctionSpec(
            name: stdlibMapHOFName("filterValues", arity: 1, fallback: "kk_map_filterValues"),
            parameters: [
                RuntimeABIParameter(name: "mapRaw", type: .intptr),
                RuntimeABIParameter(name: "fnPtr", type: .intptr),
                RuntimeABIParameter(name: "closureRaw", type: .intptr),
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "Collection"
        ),
        RuntimeABIFunctionSpec(
            name: stdlibMapHOFName("mapValues", arity: 1, fallback: "kk_map_mapValues"),
            parameters: [
                RuntimeABIParameter(name: "mapRaw", type: .intptr),
                RuntimeABIParameter(name: "fnPtr", type: .intptr),
                RuntimeABIParameter(name: "closureRaw", type: .intptr),
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "Collection"
        ),
        RuntimeABIFunctionSpec(
            name: stdlibMapHOFName("mapKeys", arity: 1, fallback: "kk_map_mapKeys"),
            parameters: [
                RuntimeABIParameter(name: "mapRaw", type: .intptr),
                RuntimeABIParameter(name: "fnPtr", type: .intptr),
                RuntimeABIParameter(name: "closureRaw", type: .intptr),
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "Collection"
        ),
        RuntimeABIFunctionSpec(
            name: stdlibMapHOFName("mapKeysTo", arity: 2, fallback: "kk_map_mapKeysTo"),
            parameters: [
                RuntimeABIParameter(name: "mapRaw", type: .intptr),
                RuntimeABIParameter(name: "destRaw", type: .intptr),
                RuntimeABIParameter(name: "fnPtr", type: .intptr),
                RuntimeABIParameter(name: "closureRaw", type: .intptr),
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "Collection"
        ),
        RuntimeABIFunctionSpec(
            name: stdlibMapHOFName("mapValuesTo", arity: 2, fallback: "kk_map_mapValuesTo"),
            parameters: [
                RuntimeABIParameter(name: "mapRaw", type: .intptr),
                RuntimeABIParameter(name: "destRaw", type: .intptr),
                RuntimeABIParameter(name: "fnPtr", type: .intptr),
                RuntimeABIParameter(name: "closureRaw", type: .intptr),
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "Collection"
        ),
        RuntimeABIFunctionSpec(
            name: "__kk_map_entries",
            parameters: [
                RuntimeABIParameter(name: "mapRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "Collection",
            isThrowing: false
        ),
        RuntimeABIFunctionSpec(
            name: "kk_map_to_string",
            parameters: [
                RuntimeABIParameter(name: "mapRaw", type: .intptr),
            ],
            returnType: .opaquePointer,
            section: "Collection",
            isThrowing: false
        ),
        RuntimeABIFunctionSpec(
            name: stdlibMapHOFName("count", arity: 1, fallback: "kk_map_count"),
            parameters: [
                RuntimeABIParameter(name: "mapRaw", type: .intptr),
                RuntimeABIParameter(name: "fnPtr", type: .intptr),
                RuntimeABIParameter(name: "closureRaw", type: .intptr),
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "Collection"
        ),
        RuntimeABIFunctionSpec(
            name: stdlibMapHOFName("any", arity: 1, fallback: "kk_map_any"),
            parameters: [
                RuntimeABIParameter(name: "mapRaw", type: .intptr),
                RuntimeABIParameter(name: "fnPtr", type: .intptr),
                RuntimeABIParameter(name: "closureRaw", type: .intptr),
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "Collection"
        ),
        RuntimeABIFunctionSpec(
            name: stdlibMapHOFName("all", arity: 1, fallback: "kk_map_all"),
            parameters: [
                RuntimeABIParameter(name: "mapRaw", type: .intptr),
                RuntimeABIParameter(name: "fnPtr", type: .intptr),
                RuntimeABIParameter(name: "closureRaw", type: .intptr),
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "Collection"
        ),
        RuntimeABIFunctionSpec(
            name: stdlibMapHOFName("none", arity: 1, fallback: "kk_map_none"),
            parameters: [
                RuntimeABIParameter(name: "mapRaw", type: .intptr),
                RuntimeABIParameter(name: "fnPtr", type: .intptr),
                RuntimeABIParameter(name: "closureRaw", type: .intptr),
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "Collection"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_map_plus",
            parameters: [
                RuntimeABIParameter(name: "mapRaw", type: .intptr),
                RuntimeABIParameter(name: "pairRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "Collection",
            isThrowing: false
        ),
        RuntimeABIFunctionSpec(
            name: "kk_map_minus",
            parameters: [
                RuntimeABIParameter(name: "mapRaw", type: .intptr),
                RuntimeABIParameter(name: "key", type: .intptr),
            ],
            returnType: .intptr,
            section: "Collection",
            isThrowing: false
        ),
        RuntimeABIFunctionSpec(
            name: "__kk_map_iterator",
            parameters: [
                RuntimeABIParameter(name: "mapRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "Collection",
            isThrowing: false
        ),
        RuntimeABIFunctionSpec(
            name: "__kk_map_iterator_hasNext",
            parameters: [
                RuntimeABIParameter(name: "iterRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "Collection",
            isThrowing: false
        ),
        RuntimeABIFunctionSpec(
            name: "__kk_map_iterator_next",
            parameters: [
                RuntimeABIParameter(name: "iterRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "Collection",
            isThrowing: false
        ),
        RuntimeABIFunctionSpec(
            name: "__kk_mutable_map_iterator",
            parameters: [
                RuntimeABIParameter(name: "mapRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "Collection",
            isThrowing: false
        ),
        RuntimeABIFunctionSpec(
            name: "__kk_mutable_map_iterator_hasNext",
            parameters: [
                RuntimeABIParameter(name: "iterRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "Collection",
            isThrowing: false
        ),
        RuntimeABIFunctionSpec(
            name: "__kk_mutable_map_iterator_next",
            parameters: [
                RuntimeABIParameter(name: "iterRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "Collection",
            isThrowing: false
        ),
        RuntimeABIFunctionSpec(
            name: "__kk_mutable_map_iterator_remove",
            parameters: [
                RuntimeABIParameter(name: "iterRaw", type: .intptr),
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "Collection"
        ),
        // Array
        RuntimeABIFunctionSpec(
            name: "kk_array_of",
            parameters: [
                RuntimeABIParameter(name: "elements", type: .intptr),
                RuntimeABIParameter(name: "count", type: .intptr),
            ],
            returnType: .intptr,
            section: "Collection",
            isThrowing: false
        ),
        RuntimeABIFunctionSpec(
            name: "__kk_array_size",
            parameters: [
                RuntimeABIParameter(name: "arrayRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "Collection",
            isThrowing: false
        ),
        RuntimeABIFunctionSpec(
            name: "kk_array_is_empty",
            parameters: [
                RuntimeABIParameter(name: "arrayRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "Collection",
            isThrowing: false
        ),
        RuntimeABIFunctionSpec(
            name: "kk_empty_array",
            parameters: [],
            returnType: .intptr,
            section: "Collection"
        ),
        RuntimeABIFunctionSpec(
            name: "__kk_array_contentDeepEquals",
            parameters: [
                RuntimeABIParameter(name: "arrayRaw", type: .intptr),
                RuntimeABIParameter(name: "otherRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "Collection"
        ),
        RuntimeABIFunctionSpec(
            name: "__kk_array_contentDeepToString",
            parameters: [
                RuntimeABIParameter(name: "arrayRaw", type: .intptr),
            ],
            returnType: .opaquePointer,
            section: "Collection"
        ),
        RuntimeABIFunctionSpec(
            name: "__kk_array_contentDeepHashCode",
            parameters: [
                RuntimeABIParameter(name: "arrayRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "Collection"
        ),
        // Array conversion (STDLIB-087)
        RuntimeABIFunctionSpec(
            name: "__kk_array_toList",
            parameters: [
                RuntimeABIParameter(name: "arrayRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "Collection",
            isThrowing: false
        ),
        RuntimeABIFunctionSpec(
            name: "kk_array_toMutableList",
            parameters: [
                RuntimeABIParameter(name: "arrayRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "Collection",
            isThrowing: false
        ),
        // Primitive array to List conversions
        RuntimeABIFunctionSpec(
            name: "__kk_intArray_toList",
            parameters: [
                RuntimeABIParameter(name: "arrayRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "Collection"
        ),
        RuntimeABIFunctionSpec(
            name: "__kk_longArray_toList",
            parameters: [
                RuntimeABIParameter(name: "arrayRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "Collection"
        ),
        RuntimeABIFunctionSpec(
            name: "__kk_byteArray_toList",
            parameters: [
                RuntimeABIParameter(name: "arrayRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "Collection"
        ),
        RuntimeABIFunctionSpec(
            name: "__kk_shortArray_toList",
            parameters: [
                RuntimeABIParameter(name: "arrayRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "Collection"
        ),
        RuntimeABIFunctionSpec(
            name: "__kk_uIntArray_toList",
            parameters: [
                RuntimeABIParameter(name: "arrayRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "Collection"
        ),
        RuntimeABIFunctionSpec(
            name: "__kk_uLongArray_toList",
            parameters: [
                RuntimeABIParameter(name: "arrayRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "Collection"
        ),
        RuntimeABIFunctionSpec(
            name: "__kk_doubleArray_toList",
            parameters: [
                RuntimeABIParameter(name: "arrayRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "Collection"
        ),
        RuntimeABIFunctionSpec(
            name: "__kk_floatArray_toList",
            parameters: [
                RuntimeABIParameter(name: "arrayRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "Collection"
        ),
        RuntimeABIFunctionSpec(
            name: "__kk_booleanArray_toList",
            parameters: [
                RuntimeABIParameter(name: "arrayRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "Collection"
        ),
        RuntimeABIFunctionSpec(
            name: "__kk_charArray_toList",
            parameters: [
                RuntimeABIParameter(name: "arrayRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "Collection"
        ),
        RuntimeABIFunctionSpec(
            name: "__kk_uByteArray_toList",
            parameters: [
                RuntimeABIParameter(name: "arrayRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "Collection"
        ),
        RuntimeABIFunctionSpec(
            name: "__kk_uShortArray_toList",
            parameters: [
                RuntimeABIParameter(name: "arrayRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "Collection"
        ),
        // Signed primitive array to unsigned primitive array view conversions
        RuntimeABIFunctionSpec(
            name: "__kk_byteArray_asUByteArray",
            parameters: [
                RuntimeABIParameter(name: "arrayRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "Collection",
            isThrowing: false
        ),
        RuntimeABIFunctionSpec(
            name: "__kk_shortArray_asUShortArray",
            parameters: [
                RuntimeABIParameter(name: "arrayRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "Collection",
            isThrowing: false
        ),
        RuntimeABIFunctionSpec(
            name: "__kk_intArray_asUIntArray",
            parameters: [
                RuntimeABIParameter(name: "arrayRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "Collection",
            isThrowing: false
        ),
        RuntimeABIFunctionSpec(
            name: "__kk_longArray_asULongArray",
            parameters: [
                RuntimeABIParameter(name: "arrayRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "Collection",
            isThrowing: false
        ),
        // Primitive and generic array asList view conversions
        RuntimeABIFunctionSpec(
            name: "__kk_array_asList",
            parameters: [
                RuntimeABIParameter(name: "arrayRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "Collection"
        ),
        RuntimeABIFunctionSpec(
            name: "__kk_intArray_asList",
            parameters: [
                RuntimeABIParameter(name: "arrayRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "Collection"
        ),
        RuntimeABIFunctionSpec(
            name: "__kk_longArray_asList",
            parameters: [
                RuntimeABIParameter(name: "arrayRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "Collection"
        ),
        RuntimeABIFunctionSpec(
            name: "__kk_shortArray_asList",
            parameters: [
                RuntimeABIParameter(name: "arrayRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "Collection"
        ),
        RuntimeABIFunctionSpec(
            name: "__kk_byteArray_asList",
            parameters: [
                RuntimeABIParameter(name: "arrayRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "Collection"
        ),
        RuntimeABIFunctionSpec(
            name: "__kk_charArray_asList",
            parameters: [
                RuntimeABIParameter(name: "arrayRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "Collection"
        ),
        RuntimeABIFunctionSpec(
            name: "__kk_booleanArray_asList",
            parameters: [
                RuntimeABIParameter(name: "arrayRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "Collection"
        ),
        RuntimeABIFunctionSpec(
            name: "__kk_doubleArray_asList",
            parameters: [
                RuntimeABIParameter(name: "arrayRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "Collection"
        ),
        RuntimeABIFunctionSpec(
            name: "__kk_floatArray_asList",
            parameters: [
                RuntimeABIParameter(name: "arrayRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "Collection"
        ),
        RuntimeABIFunctionSpec(
            name: "__kk_uByteArray_asList",
            parameters: [
                RuntimeABIParameter(name: "arrayRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "Collection"
        ),
        RuntimeABIFunctionSpec(
            name: "__kk_uShortArray_asList",
            parameters: [
                RuntimeABIParameter(name: "arrayRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "Collection"
        ),
        RuntimeABIFunctionSpec(
            name: "__kk_uIntArray_asList",
            parameters: [
                RuntimeABIParameter(name: "arrayRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "Collection"
        ),
        RuntimeABIFunctionSpec(
            name: "__kk_uLongArray_asList",
            parameters: [
                RuntimeABIParameter(name: "arrayRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "Collection"
        ),
        // Unsigned primitive array to signed primitive array view conversions
        RuntimeABIFunctionSpec(
            name: "__kk_uByteArray_asByteArray",
            parameters: [
                RuntimeABIParameter(name: "arrayRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "Collection",
            isThrowing: false
        ),
        RuntimeABIFunctionSpec(
            name: "__kk_uShortArray_asShortArray",
            parameters: [
                RuntimeABIParameter(name: "arrayRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "Collection",
            isThrowing: false
        ),
        RuntimeABIFunctionSpec(
            name: "__kk_uIntArray_asIntArray",
            parameters: [
                RuntimeABIParameter(name: "arrayRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "Collection",
            isThrowing: false
        ),
        RuntimeABIFunctionSpec(
            name: "__kk_uLongArray_asLongArray",
            parameters: [
                RuntimeABIParameter(name: "arrayRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "Collection",
            isThrowing: false
        ),
        // Primitive array size property
        RuntimeABIFunctionSpec(
            name: "__kk_intArray_size",
            parameters: [
                RuntimeABIParameter(name: "arrayRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "Collection"
        ),
        RuntimeABIFunctionSpec(
            name: "__kk_longArray_size",
            parameters: [
                RuntimeABIParameter(name: "arrayRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "Collection"
        ),
        RuntimeABIFunctionSpec(
            name: "__kk_byteArray_size",
            parameters: [
                RuntimeABIParameter(name: "arrayRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "Collection"
        ),
        RuntimeABIFunctionSpec(
            name: "__kk_shortArray_size",
            parameters: [
                RuntimeABIParameter(name: "arrayRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "Collection"
        ),
        RuntimeABIFunctionSpec(
            name: "__kk_uIntArray_size",
            parameters: [
                RuntimeABIParameter(name: "arrayRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "Collection"
        ),
        RuntimeABIFunctionSpec(
            name: "__kk_uLongArray_size",
            parameters: [
                RuntimeABIParameter(name: "arrayRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "Collection"
        ),
        RuntimeABIFunctionSpec(
            name: "__kk_doubleArray_size",
            parameters: [
                RuntimeABIParameter(name: "arrayRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "Collection"
        ),
        RuntimeABIFunctionSpec(
            name: "__kk_floatArray_size",
            parameters: [
                RuntimeABIParameter(name: "arrayRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "Collection"
        ),
        RuntimeABIFunctionSpec(
            name: "__kk_booleanArray_size",
            parameters: [
                RuntimeABIParameter(name: "arrayRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "Collection"
        ),
        RuntimeABIFunctionSpec(
            name: "__kk_charArray_size",
            parameters: [
                RuntimeABIParameter(name: "arrayRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "Collection"
        ),
        RuntimeABIFunctionSpec(
            name: "__kk_uByteArray_size",
            parameters: [
                RuntimeABIParameter(name: "arrayRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "Collection"
        ),
        RuntimeABIFunctionSpec(
            name: "__kk_uShortArray_size",
            parameters: [
                RuntimeABIParameter(name: "arrayRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "Collection"
        ),
        // Array utility functions (STDLIB-089)
        RuntimeABIFunctionSpec(
            name: "__kk_array_copyOf",
            parameters: [
                RuntimeABIParameter(name: "arrayRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "Collection",
            isThrowing: false
        ),
        RuntimeABIFunctionSpec(
            name: "kk_array_fill",
            parameters: [
                RuntimeABIParameter(name: "arrayRaw", type: .intptr),
                RuntimeABIParameter(name: "element", type: .intptr),
            ],
            returnType: .intptr,
            section: "Collection",
            isThrowing: false
        ),
        // asSequence (STDLIB-471)
        RuntimeABIFunctionSpec(
            name: "kk_list_asSequence",
            parameters: [
                RuntimeABIParameter(name: "listRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "Collection",
            isThrowing: false
        ),
        RuntimeABIFunctionSpec(
            name: "kk_array_asSequence",
            parameters: [
                RuntimeABIParameter(name: "arrayRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "Collection",
            isThrowing: false
        ),
        // Pair (FUNC-002)
        RuntimeABIFunctionSpec(
            name: "__kk_pair_new",
            parameters: [
                RuntimeABIParameter(name: "first", type: .intptr),
                RuntimeABIParameter(name: "second", type: .intptr),
            ],
            returnType: .intptr,
            section: "Collection",
            isThrowing: false
        ),
        RuntimeABIFunctionSpec(
            name: "kk_indexed_value_new",
            parameters: [
                RuntimeABIParameter(name: "index", type: .intptr),
                RuntimeABIParameter(name: "value", type: .intptr),
            ],
            returnType: .intptr,
            section: "Collection",
            isThrowing: false
        ),
        RuntimeABIFunctionSpec(
            name: "__kk_pair_first",
            parameters: [
                RuntimeABIParameter(name: "pairRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "Collection",
            isThrowing: false
        ),
        RuntimeABIFunctionSpec(
            name: "__kk_pair_second",
            parameters: [
                RuntimeABIParameter(name: "pairRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "Collection",
            isThrowing: false
        ),
        // Triple (STDLIB-120)
        RuntimeABIFunctionSpec(
            name: "__kk_triple_new",
            parameters: [
                RuntimeABIParameter(name: "first", type: .intptr),
                RuntimeABIParameter(name: "second", type: .intptr),
                RuntimeABIParameter(name: "third", type: .intptr),
            ],
            returnType: .intptr,
            section: "Collection",
            isThrowing: false
        ),
        RuntimeABIFunctionSpec(
            name: "__kk_triple_first",
            parameters: [
                RuntimeABIParameter(name: "tripleRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "Collection",
            isThrowing: false
        ),
        RuntimeABIFunctionSpec(
            name: "__kk_triple_second",
            parameters: [
                RuntimeABIParameter(name: "tripleRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "Collection",
            isThrowing: false
        ),
        RuntimeABIFunctionSpec(
            name: "__kk_triple_third",
            parameters: [
                RuntimeABIParameter(name: "tripleRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "Collection",
            isThrowing: false
        ),
        // Builder DSL (STDLIB-002)
        RuntimeABIFunctionSpec(
            name: "__kk_build_list",
            parameters: [
                RuntimeABIParameter(name: "fnPtr", type: .intptr),
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "Collection"
        ),
        RuntimeABIFunctionSpec(
            name: "__kk_build_list_with_capacity",
            parameters: [
                RuntimeABIParameter(name: "capacity", type: .intptr),
                RuntimeABIParameter(name: "fnPtr", type: .intptr),
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "Collection"
        ),
        RuntimeABIFunctionSpec(
            name: "__kk_build_map",
            parameters: [
                RuntimeABIParameter(name: "fnPtr", type: .intptr),
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "Collection"
        ),
        RuntimeABIFunctionSpec(
            name: "__kk_build_set",
            parameters: [
                RuntimeABIParameter(name: "fnPtr", type: .intptr),
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "Collection"
        ),
        RuntimeABIFunctionSpec(
            name: "__kk_build_set_with_capacity",
            parameters: [
                RuntimeABIParameter(name: "capacity", type: .intptr),
                RuntimeABIParameter(name: "fnPtr", type: .intptr),
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "Collection"
        ),
        RuntimeABIFunctionSpec(
            name: "__kk_build_map_with_capacity",
            parameters: [
                RuntimeABIParameter(name: "capacity", type: .intptr),
                RuntimeABIParameter(name: "fnPtr", type: .intptr),
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "Collection"
        ),
        RuntimeABIFunctionSpec(
            name: "__kk_builder_list_new",
            parameters: [
                RuntimeABIParameter(name: "capacity", type: .intptr),
            ],
            returnType: .intptr,
            section: "Collection",
            isThrowing: false
        ),
        RuntimeABIFunctionSpec(
            name: "__kk_builder_set_new",
            parameters: [
                RuntimeABIParameter(name: "capacity", type: .intptr),
            ],
            returnType: .intptr,
            section: "Collection",
            isThrowing: false
        ),
        RuntimeABIFunctionSpec(
            name: "__kk_builder_map_new",
            parameters: [
                RuntimeABIParameter(name: "capacity", type: .intptr),
            ],
            returnType: .intptr,
            section: "Collection",
            isThrowing: false
        ),
        RuntimeABIFunctionSpec(
            name: "__kk_builder_list_freeze",
            parameters: [
                RuntimeABIParameter(name: "raw", type: .intptr),
            ],
            returnType: .intptr,
            section: "Collection",
            isThrowing: false
        ),
        RuntimeABIFunctionSpec(
            name: "__kk_builder_set_freeze",
            parameters: [
                RuntimeABIParameter(name: "raw", type: .intptr),
            ],
            returnType: .intptr,
            section: "Collection",
            isThrowing: false
        ),
        RuntimeABIFunctionSpec(
            name: "__kk_builder_map_freeze",
            parameters: [
                RuntimeABIParameter(name: "raw", type: .intptr),
            ],
            returnType: .intptr,
            section: "Collection",
            isThrowing: false
        ),
        RuntimeABIFunctionSpec(
            name: "__kk_mutable_list_add",
            parameters: [
                RuntimeABIParameter(name: "listRaw", type: .intptr),
                RuntimeABIParameter(name: "elem", type: .intptr),
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "Collection"
        ),
        RuntimeABIFunctionSpec(
            name: "__kk_mutable_collection_add",
            parameters: [
                RuntimeABIParameter(name: "collectionRaw", type: .intptr),
                RuntimeABIParameter(name: "elem", type: .intptr),
            ],
            returnType: .intptr,
            section: "Collection",
            isThrowing: false
        ),
        RuntimeABIFunctionSpec(
            name: "__kk_mutable_collection_remove",
            parameters: [
                RuntimeABIParameter(name: "collectionRaw", type: .intptr),
                RuntimeABIParameter(name: "elem", type: .intptr),
            ],
            returnType: .intptr,
            section: "Collection",
            isThrowing: false
        ),
        RuntimeABIFunctionSpec(
            name: "__kk_mutable_collection_clear",
            parameters: [
                RuntimeABIParameter(name: "collectionRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "Collection",
            isThrowing: false
        ),
        RuntimeABIFunctionSpec(
            name: "__kk_mutable_collection_removeAll",
            parameters: [
                RuntimeABIParameter(name: "collectionRaw", type: .intptr),
                RuntimeABIParameter(name: "elementsRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "Collection",
            isThrowing: false
        ),
        RuntimeABIFunctionSpec(
            name: "__kk_mutable_collection_retainAll",
            parameters: [
                RuntimeABIParameter(name: "collectionRaw", type: .intptr),
                RuntimeABIParameter(name: "elementsRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "Collection",
            isThrowing: false
        ),
        RuntimeABIFunctionSpec(
            name: "__kk_mutable_list_remove",
            parameters: [
                RuntimeABIParameter(name: "listRaw", type: .intptr),
                RuntimeABIParameter(name: "elem", type: .intptr),
            ],
            returnType: .intptr,
            section: "Collection",
            isThrowing: false
        ),
        RuntimeABIFunctionSpec(
            name: "__kk_mutable_collection_addAll",
            parameters: [
                RuntimeABIParameter(name: "collectionRaw", type: .intptr),
                RuntimeABIParameter(name: "elementsRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "Collection"
        ),
        RuntimeABIFunctionSpec(
            name: "__kk_mutable_list_addAll",
            parameters: [
                RuntimeABIParameter(name: "listRaw", type: .intptr),
                RuntimeABIParameter(name: "collectionRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "Collection",
            isThrowing: false
        ),
        RuntimeABIFunctionSpec(
            name: "__kk_mutable_collection_addAll_sequence",
            parameters: [
                RuntimeABIParameter(name: "collectionRaw", type: .intptr),
                RuntimeABIParameter(name: "sequenceRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "Collection",
            isThrowing: false
        ),
        RuntimeABIFunctionSpec(
            name: "__kk_mutable_collection_addAll_iterable",
            parameters: [
                RuntimeABIParameter(name: "collectionRaw", type: .intptr),
                RuntimeABIParameter(name: "iterableRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "Collection"
        ),
        RuntimeABIFunctionSpec(
            name: "__kk_mutable_list_addAll_sequence",
            parameters: [
                RuntimeABIParameter(name: "listRaw", type: .intptr),
                RuntimeABIParameter(name: "sequenceRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "Collection",
            isThrowing: false
        ),
        RuntimeABIFunctionSpec(
            name: "__kk_mutable_list_addAll_iterable",
            parameters: [
                RuntimeABIParameter(name: "listRaw", type: .intptr),
                RuntimeABIParameter(name: "iterableRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "Collection"
        ),
        RuntimeABIFunctionSpec(
            name: "__kk_mutable_list_removeAll",
            parameters: [
                RuntimeABIParameter(name: "listRaw", type: .intptr),
                RuntimeABIParameter(name: "collectionRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "Collection",
            isThrowing: false
        ),
        RuntimeABIFunctionSpec(
            name: "__kk_mutable_list_retainAll",
            parameters: [
                RuntimeABIParameter(name: "listRaw", type: .intptr),
                RuntimeABIParameter(name: "collectionRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "Collection",
            isThrowing: false
        ),
        RuntimeABIFunctionSpec(
            name: "__kk_mutable_list_removeAt",
            parameters: [
                RuntimeABIParameter(name: "listRaw", type: .intptr),
                RuntimeABIParameter(name: "index", type: .intptr),
            ],
            returnType: .intptr,
            section: "Collection",
            isThrowing: false
        ),
        RuntimeABIFunctionSpec(
            name: "__kk_mutable_list_removeFirst",
            parameters: [
                RuntimeABIParameter(name: "listRaw", type: .intptr),
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "Collection"
        ),
        RuntimeABIFunctionSpec(
            name: "__kk_mutable_list_removeFirstOrNull",
            parameters: [
                RuntimeABIParameter(name: "listRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "Collection",
            isThrowing: false
        ),
        RuntimeABIFunctionSpec(
            name: "__kk_mutable_list_removeLast",
            parameters: [
                RuntimeABIParameter(name: "listRaw", type: .intptr),
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "Collection"
        ),
        RuntimeABIFunctionSpec(
            name: "__kk_mutable_list_removeLastOrNull",
            parameters: [
                RuntimeABIParameter(name: "listRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "Collection",
            isThrowing: false
        ),
        RuntimeABIFunctionSpec(
            name: "__kk_mutable_list_clear",
            parameters: [
                RuntimeABIParameter(name: "listRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "Collection",
            isThrowing: false
        ),
        RuntimeABIFunctionSpec(
            name: "__kk_mutable_list_add_at",
            parameters: [
                RuntimeABIParameter(name: "listRaw", type: .intptr),
                RuntimeABIParameter(name: "index", type: .intptr),
                RuntimeABIParameter(name: "element", type: .intptr),
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "Collection"
        ),
        RuntimeABIFunctionSpec(
            name: "__kk_mutable_list_addAll_at",
            parameters: [
                RuntimeABIParameter(name: "listRaw", type: .intptr),
                RuntimeABIParameter(name: "index", type: .intptr),
                RuntimeABIParameter(name: "collectionRaw", type: .intptr),
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "Collection"
        ),
        RuntimeABIFunctionSpec(
            name: "__kk_mutable_list_set",
            parameters: [
                RuntimeABIParameter(name: "listRaw", type: .intptr),
                RuntimeABIParameter(name: "index", type: .intptr),
                RuntimeABIParameter(name: "element", type: .intptr),
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "Collection"
        ),
        RuntimeABIFunctionSpec(
            name: "__kk_mutable_list_shuffle",
            parameters: [
                RuntimeABIParameter(name: "listRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "Collection",
            isThrowing: false
        ),
        RuntimeABIFunctionSpec(
            name: "__kk_mutable_list_reverse",
            parameters: [
                RuntimeABIParameter(name: "listRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "Collection",
            isThrowing: false
        ),
        RuntimeABIFunctionSpec(
            name: "__kk_mutable_list_sortDescending",
            parameters: [
                RuntimeABIParameter(name: "listRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "Collection"
        ),
        RuntimeABIFunctionSpec(
            name: "__kk_mutable_list_sortDescending_primitive",
            parameters: [
                RuntimeABIParameter(name: "listRaw", type: .intptr),
                RuntimeABIParameter(name: "kindRaw", type: .int32),
            ],
            returnType: .intptr,
            section: "Collection"
        ),
        RuntimeABIFunctionSpec(
            name: "__kk_mutable_set_add",
            parameters: [
                RuntimeABIParameter(name: "setRaw", type: .intptr),
                RuntimeABIParameter(name: "elem", type: .intptr),
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "Collection"
        ),
        RuntimeABIFunctionSpec(
            name: "__kk_mutable_set_remove",
            parameters: [
                RuntimeABIParameter(name: "setRaw", type: .intptr),
                RuntimeABIParameter(name: "elem", type: .intptr),
            ],
            returnType: .intptr,
            section: "Collection"
        ),
        RuntimeABIFunctionSpec(
            name: "__kk_mutable_set_clear",
            parameters: [
                RuntimeABIParameter(name: "setRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "Collection",
            isThrowing: false
        ),
        RuntimeABIFunctionSpec(
            name: "__kk_mutable_set_addAll",
            parameters: [
                RuntimeABIParameter(name: "setRaw", type: .intptr),
                RuntimeABIParameter(name: "collectionRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "Collection",
            isThrowing: false
        ),
        RuntimeABIFunctionSpec(
            name: "__kk_mutable_set_addAll_sequence",
            parameters: [
                RuntimeABIParameter(name: "setRaw", type: .intptr),
                RuntimeABIParameter(name: "sequenceRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "Collection",
            isThrowing: false
        ),
        RuntimeABIFunctionSpec(
            name: "__kk_mutable_set_addAll_iterable",
            parameters: [
                RuntimeABIParameter(name: "setRaw", type: .intptr),
                RuntimeABIParameter(name: "iterableRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "Collection"
        ),
        RuntimeABIFunctionSpec(
            name: "__kk_mutable_set_removeAll",
            parameters: [
                RuntimeABIParameter(name: "setRaw", type: .intptr),
                RuntimeABIParameter(name: "collectionRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "Collection",
            isThrowing: false
        ),
        RuntimeABIFunctionSpec(
            name: "__kk_mutable_set_retainAll",
            parameters: [
                RuntimeABIParameter(name: "setRaw", type: .intptr),
                RuntimeABIParameter(name: "collectionRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "Collection",
            isThrowing: false
        ),
        RuntimeABIFunctionSpec(
            name: "__kk_mutable_map_put",
            parameters: [
                RuntimeABIParameter(name: "mapRaw", type: .intptr),
                RuntimeABIParameter(name: "key", type: .intptr),
                RuntimeABIParameter(name: "value", type: .intptr),
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "Collection"
        ),
        RuntimeABIFunctionSpec(
            name: "__kk_mutable_map_remove",
            parameters: [
                RuntimeABIParameter(name: "mapRaw", type: .intptr),
                RuntimeABIParameter(name: "key", type: .intptr),
            ],
            returnType: .intptr,
            section: "Collection",
            isThrowing: false
        ),
        RuntimeABIFunctionSpec(
            name: "__kk_mutable_map_clear",
            parameters: [
                RuntimeABIParameter(name: "mapRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "Collection",
            isThrowing: false
        ),
        RuntimeABIFunctionSpec(
            name: "__kk_mutable_map_putAll",
            parameters: [
                RuntimeABIParameter(name: "mapRaw", type: .intptr),
                RuntimeABIParameter(name: "entriesRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "Collection",
            isThrowing: false
        ),
        RuntimeABIFunctionSpec(
            name: "__kk_mutable_map_plusAssign_pair",
            parameters: [
                RuntimeABIParameter(name: "mapRaw", type: .intptr),
                RuntimeABIParameter(name: "pairRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "Collection",
            isThrowing: false
        ),
        RuntimeABIFunctionSpec(
            name: "__kk_mutable_map_withDefault",
            parameters: [
                RuntimeABIParameter(name: "mapRaw", type: .intptr),
                RuntimeABIParameter(name: "fnPtr", type: .intptr),
                RuntimeABIParameter(name: "closureRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "Collection",
            isThrowing: false
        ),
        RuntimeABIFunctionSpec(
            name: "__kk_mutable_map_entry_setValue",
            parameters: [
                RuntimeABIParameter(name: "entryRaw", type: .intptr),
                RuntimeABIParameter(name: "value", type: .intptr),
            ],
            returnType: .intptr,
            section: "Collection",
            isThrowing: false
        ),
    ]
}
