public extension RuntimeABISpec {
    static let collectionFunctions: [RuntimeABIFunctionSpec] = [
        // List
        RuntimeABIFunctionSpec(
            name: "kk_list_of",
            parameters: [
                RuntimeABIParameter(name: "arrayRaw", type: .intptr),
                RuntimeABIParameter(name: "count", type: .intptr),
            ],
            returnType: .intptr,
            section: "Collection"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_list_of_not_null",
            parameters: [
                RuntimeABIParameter(name: "arrayRaw", type: .intptr),
                RuntimeABIParameter(name: "count", type: .intptr),
            ],
            returnType: .intptr,
            section: "Collection"
        ),
        // STDLIB-410: emptyList
        RuntimeABIFunctionSpec(
            name: "kk_emptyList",
            parameters: [],
            returnType: .intptr,
            section: "Collection"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_list_size",
            parameters: [
                RuntimeABIParameter(name: "listRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "Collection"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_list_get",
            parameters: [
                RuntimeABIParameter(name: "listRaw", type: .intptr),
                RuntimeABIParameter(name: "index", type: .intptr),
            ],
            returnType: .intptr,
            section: "Collection"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_list_component1",
            parameters: [RuntimeABIParameter(name: "listRaw", type: .intptr)],
            returnType: .intptr,
            section: "Collection"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_list_component2",
            parameters: [RuntimeABIParameter(name: "listRaw", type: .intptr)],
            returnType: .intptr,
            section: "Collection"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_list_component3",
            parameters: [RuntimeABIParameter(name: "listRaw", type: .intptr)],
            returnType: .intptr,
            section: "Collection"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_list_component4",
            parameters: [RuntimeABIParameter(name: "listRaw", type: .intptr)],
            returnType: .intptr,
            section: "Collection"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_list_component5",
            parameters: [RuntimeABIParameter(name: "listRaw", type: .intptr)],
            returnType: .intptr,
            section: "Collection"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_list_contains",
            parameters: [
                RuntimeABIParameter(name: "listRaw", type: .intptr),
                RuntimeABIParameter(name: "element", type: .intptr),
            ],
            returnType: .intptr,
            section: "Collection"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_list_is_empty",
            parameters: [
                RuntimeABIParameter(name: "listRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "Collection"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_list_iterator",
            parameters: [
                RuntimeABIParameter(name: "listRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "Collection"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_list_iterator_hasNext",
            parameters: [
                RuntimeABIParameter(name: "iterRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "Collection"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_list_iterator_next",
            parameters: [
                RuntimeABIParameter(name: "iterRaw", type: .intptr),
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
            name: "kk_list_to_string",
            parameters: [
                RuntimeABIParameter(name: "listRaw", type: .intptr),
            ],
            returnType: .opaquePointer,
            section: "Collection"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_list_to_mutable_list",
            parameters: [
                RuntimeABIParameter(name: "listRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "Collection"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_list_joinToString",
            parameters: [
                RuntimeABIParameter(name: "listRaw", type: .intptr),
                RuntimeABIParameter(name: "separatorRaw", type: .intptr),
                RuntimeABIParameter(name: "prefixRaw", type: .intptr),
                RuntimeABIParameter(name: "postfixRaw", type: .intptr),
            ],
            returnType: .opaquePointer,
            section: "Collection"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_list_to_set",
            parameters: [
                RuntimeABIParameter(name: "listRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "Collection"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_set_to_set",
            parameters: [
                RuntimeABIParameter(name: "setRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "Collection"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_list_to_mutable_set",
            parameters: [
                RuntimeABIParameter(name: "listRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "Collection"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_set_to_mutable_set",
            parameters: [
                RuntimeABIParameter(name: "setRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "Collection"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_list_firstOrNull",
            parameters: [
                RuntimeABIParameter(name: "listRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "Collection"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_list_lastOrNull",
            parameters: [
                RuntimeABIParameter(name: "listRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "Collection"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_list_subList",
            parameters: [
                RuntimeABIParameter(name: "listRaw", type: .intptr),
                RuntimeABIParameter(name: "fromIndex", type: .intptr),
                RuntimeABIParameter(name: "toIndex", type: .intptr),
            ],
            returnType: .intptr,
            section: "Collection"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_list_toMap",
            parameters: [
                RuntimeABIParameter(name: "listRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "Collection"
        ),
        // Set
        RuntimeABIFunctionSpec(
            name: "kk_set_of",
            parameters: [
                RuntimeABIParameter(name: "arrayRaw", type: .intptr),
                RuntimeABIParameter(name: "count", type: .intptr),
            ],
            returnType: .intptr,
            section: "Collection"
        ),
        // STDLIB-410: emptySet
        RuntimeABIFunctionSpec(
            name: "kk_emptySet",
            parameters: [],
            returnType: .intptr,
            section: "Collection"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_set_size",
            parameters: [
                RuntimeABIParameter(name: "setRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "Collection"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_set_contains",
            parameters: [
                RuntimeABIParameter(name: "setRaw", type: .intptr),
                RuntimeABIParameter(name: "element", type: .intptr),
            ],
            returnType: .intptr,
            section: "Collection"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_set_is_empty",
            parameters: [
                RuntimeABIParameter(name: "setRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "Collection"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_set_toList",
            parameters: [
                RuntimeABIParameter(name: "setRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "Collection"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_collection_toList",
            parameters: [
                RuntimeABIParameter(name: "collRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "Collection"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_collection_size",
            parameters: [
                RuntimeABIParameter(name: "collRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "Collection"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_collection_isEmpty",
            parameters: [
                RuntimeABIParameter(name: "collRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "Collection"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_set_sorted",
            parameters: [
                RuntimeABIParameter(name: "setRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "Collection"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_set_sortedDescending",
            parameters: [
                RuntimeABIParameter(name: "setRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "Collection"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_set_intersect",
            parameters: [
                RuntimeABIParameter(name: "setRaw", type: .intptr),
                RuntimeABIParameter(name: "otherRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "Collection"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_set_union",
            parameters: [
                RuntimeABIParameter(name: "setRaw", type: .intptr),
                RuntimeABIParameter(name: "otherRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "Collection"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_set_subtract",
            parameters: [
                RuntimeABIParameter(name: "setRaw", type: .intptr),
                RuntimeABIParameter(name: "otherRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "Collection"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_set_to_string",
            parameters: [
                RuntimeABIParameter(name: "setRaw", type: .intptr),
            ],
            returnType: .opaquePointer,
            section: "Collection"
        ),
    ] + Self.collectionHOFFunctions + [
        // Map
        RuntimeABIFunctionSpec(
            name: "kk_map_of",
            parameters: [
                RuntimeABIParameter(name: "keysArrayRaw", type: .intptr),
                RuntimeABIParameter(name: "valuesArrayRaw", type: .intptr),
                RuntimeABIParameter(name: "count", type: .intptr),
            ],
            returnType: .intptr,
            section: "Collection"
        ),
        // STDLIB-410: emptyMap
        RuntimeABIFunctionSpec(
            name: "kk_emptyMap",
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
            section: "Collection"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_map_get",
            parameters: [
                RuntimeABIParameter(name: "mapRaw", type: .intptr),
                RuntimeABIParameter(name: "key", type: .intptr),
            ],
            returnType: .intptr,
            section: "Collection"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_map_contains_key",
            parameters: [
                RuntimeABIParameter(name: "mapRaw", type: .intptr),
                RuntimeABIParameter(name: "key", type: .intptr),
            ],
            returnType: .intptr,
            section: "Collection"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_map_contains_value",
            parameters: [
                RuntimeABIParameter(name: "mapRaw", type: .intptr),
                RuntimeABIParameter(name: "value", type: .intptr),
            ],
            returnType: .intptr,
            section: "Collection"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_map_is_empty",
            parameters: [
                RuntimeABIParameter(name: "mapRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "Collection"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_map_forEach",
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
            name: "kk_map_map",
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
            name: "kk_map_filter",
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
            name: "kk_map_getValue",
            parameters: [
                RuntimeABIParameter(name: "mapRaw", type: .intptr),
                RuntimeABIParameter(name: "key", type: .intptr),
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "Collection"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_map_getOrDefault",
            parameters: [
                RuntimeABIParameter(name: "mapRaw", type: .intptr),
                RuntimeABIParameter(name: "key", type: .intptr),
                RuntimeABIParameter(name: "defaultValue", type: .intptr),
            ],
            returnType: .intptr,
            section: "Collection"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_map_getOrElse",
            parameters: [
                RuntimeABIParameter(name: "mapRaw", type: .intptr),
                RuntimeABIParameter(name: "key", type: .intptr),
                RuntimeABIParameter(name: "fnPtr", type: .intptr),
                RuntimeABIParameter(name: "closureRaw", type: .intptr),
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "Collection"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_map_mapValues",
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
            name: "kk_map_mapKeys",
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
            name: "kk_map_keys",
            parameters: [
                RuntimeABIParameter(name: "mapRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "Collection"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_map_values",
            parameters: [
                RuntimeABIParameter(name: "mapRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "Collection"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_map_entries",
            parameters: [
                RuntimeABIParameter(name: "mapRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "Collection"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_map_to_string",
            parameters: [
                RuntimeABIParameter(name: "mapRaw", type: .intptr),
            ],
            returnType: .opaquePointer,
            section: "Collection"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_map_count",
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
            name: "kk_map_any",
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
            name: "kk_map_all",
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
            name: "kk_map_none",
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
            name: "kk_map_toList",
            parameters: [
                RuntimeABIParameter(name: "mapRaw", type: .intptr),
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
            section: "Collection"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_map_minus",
            parameters: [
                RuntimeABIParameter(name: "mapRaw", type: .intptr),
                RuntimeABIParameter(name: "key", type: .intptr),
            ],
            returnType: .intptr,
            section: "Collection"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_map_to_mutable_map",
            parameters: [
                RuntimeABIParameter(name: "mapRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "Collection"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_map_iterator",
            parameters: [
                RuntimeABIParameter(name: "mapRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "Collection"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_map_iterator_hasNext",
            parameters: [
                RuntimeABIParameter(name: "iterRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "Collection"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_map_iterator_next",
            parameters: [
                RuntimeABIParameter(name: "iterRaw", type: .intptr),
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
            section: "Collection"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_array_size",
            parameters: [
                RuntimeABIParameter(name: "arrayRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "Collection"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_array_is_empty",
            parameters: [
                RuntimeABIParameter(name: "arrayRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "Collection"
        ),
        // Array conversion (STDLIB-087)
        RuntimeABIFunctionSpec(
            name: "kk_array_toList",
            parameters: [
                RuntimeABIParameter(name: "arrayRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "Collection"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_array_toMutableList",
            parameters: [
                RuntimeABIParameter(name: "arrayRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "Collection"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_list_toTypedArray",
            parameters: [
                RuntimeABIParameter(name: "listRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "Collection"
        ),
        // Array higher-order functions (STDLIB-088)
        RuntimeABIFunctionSpec(
            name: "kk_array_map",
            parameters: [
                RuntimeABIParameter(name: "arrayRaw", type: .intptr),
                RuntimeABIParameter(name: "lambdaRaw", type: .intptr),
                RuntimeABIParameter(name: "captureRaw", type: .intptr),
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "Collection"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_array_filter",
            parameters: [
                RuntimeABIParameter(name: "arrayRaw", type: .intptr),
                RuntimeABIParameter(name: "lambdaRaw", type: .intptr),
                RuntimeABIParameter(name: "captureRaw", type: .intptr),
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "Collection"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_array_forEach",
            parameters: [
                RuntimeABIParameter(name: "arrayRaw", type: .intptr),
                RuntimeABIParameter(name: "lambdaRaw", type: .intptr),
                RuntimeABIParameter(name: "captureRaw", type: .intptr),
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "Collection"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_array_any",
            parameters: [
                RuntimeABIParameter(name: "arrayRaw", type: .intptr),
                RuntimeABIParameter(name: "lambdaRaw", type: .intptr),
                RuntimeABIParameter(name: "captureRaw", type: .intptr),
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "Collection"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_array_none",
            parameters: [
                RuntimeABIParameter(name: "arrayRaw", type: .intptr),
                RuntimeABIParameter(name: "lambdaRaw", type: .intptr),
                RuntimeABIParameter(name: "captureRaw", type: .intptr),
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "Collection"
        ),
        // Array utility functions (STDLIB-089)
        RuntimeABIFunctionSpec(
            name: "kk_array_copyOf",
            parameters: [
                RuntimeABIParameter(name: "arrayRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "Collection"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_array_copyOfRange",
            parameters: [
                RuntimeABIParameter(name: "arrayRaw", type: .intptr),
                RuntimeABIParameter(name: "fromIndex", type: .intptr),
                RuntimeABIParameter(name: "toIndex", type: .intptr),
            ],
            returnType: .intptr,
            section: "Collection"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_array_fill",
            parameters: [
                RuntimeABIParameter(name: "arrayRaw", type: .intptr),
                RuntimeABIParameter(name: "element", type: .intptr),
            ],
            returnType: .intptr,
            section: "Collection"
        ),
        // asSequence (STDLIB-471)
        RuntimeABIFunctionSpec(
            name: "kk_list_asSequence",
            parameters: [
                RuntimeABIParameter(name: "listRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "Collection"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_array_asSequence",
            parameters: [
                RuntimeABIParameter(name: "arrayRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "Collection"
        ),
        // Pair (FUNC-002)
        RuntimeABIFunctionSpec(
            name: "kk_pair_new",
            parameters: [
                RuntimeABIParameter(name: "first", type: .intptr),
                RuntimeABIParameter(name: "second", type: .intptr),
            ],
            returnType: .intptr,
            section: "Collection"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_pair_first",
            parameters: [
                RuntimeABIParameter(name: "pairRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "Collection"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_pair_second",
            parameters: [
                RuntimeABIParameter(name: "pairRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "Collection"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_pair_to_string",
            parameters: [
                RuntimeABIParameter(name: "pairRaw", type: .intptr),
            ],
            returnType: .opaquePointer,
            section: "Collection"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_pair_toList",
            parameters: [
                RuntimeABIParameter(name: "pairRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "Collection"
        ),
        // Triple (STDLIB-120)
        RuntimeABIFunctionSpec(
            name: "kk_triple_new",
            parameters: [
                RuntimeABIParameter(name: "first", type: .intptr),
                RuntimeABIParameter(name: "second", type: .intptr),
                RuntimeABIParameter(name: "third", type: .intptr),
            ],
            returnType: .intptr,
            section: "Collection"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_triple_first",
            parameters: [
                RuntimeABIParameter(name: "tripleRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "Collection"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_triple_second",
            parameters: [
                RuntimeABIParameter(name: "tripleRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "Collection"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_triple_third",
            parameters: [
                RuntimeABIParameter(name: "tripleRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "Collection"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_triple_to_string",
            parameters: [
                RuntimeABIParameter(name: "tripleRaw", type: .intptr),
            ],
            returnType: .opaquePointer,
            section: "Collection"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_triple_toList",
            parameters: [
                RuntimeABIParameter(name: "tripleRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "Collection"
        ),
        // Builder DSL (STDLIB-002)
        RuntimeABIFunctionSpec(
            name: "kk_build_string",
            parameters: [
                RuntimeABIParameter(name: "fnPtr", type: .intptr),
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "Collection"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_build_list",
            parameters: [
                RuntimeABIParameter(name: "fnPtr", type: .intptr),
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "Collection"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_build_list_with_capacity",
            parameters: [
                RuntimeABIParameter(name: "capacity", type: .intptr),
                RuntimeABIParameter(name: "fnPtr", type: .intptr),
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "Collection"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_build_map",
            parameters: [
                RuntimeABIParameter(name: "fnPtr", type: .intptr),
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "Collection"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_build_set",
            parameters: [
                RuntimeABIParameter(name: "fnPtr", type: .intptr),
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "Collection"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_string_builder_append",
            parameters: [
                RuntimeABIParameter(name: "strRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "Collection"
        ),
        // StringBuilder enhancements (STDLIB-311) — buildString DSL helpers
        // (object-oriented StringBuilder API lives in RuntimeABISpec+StringBuilder.swift)
        RuntimeABIFunctionSpec(
            name: "kk_string_builder_append_line",
            parameters: [
                RuntimeABIParameter(name: "valueRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "Collection"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_string_builder_append_line_noarg",
            parameters: [],
            returnType: .intptr,
            section: "Collection"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_string_builder_append_range",
            parameters: [
                RuntimeABIParameter(name: "csqRaw", type: .intptr),
                RuntimeABIParameter(name: "startIndex", type: .intptr),
                RuntimeABIParameter(name: "endIndex", type: .intptr),
            ],
            returnType: .intptr,
            section: "Collection"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_string_builder_insert",
            parameters: [
                RuntimeABIParameter(name: "index", type: .intptr),
                RuntimeABIParameter(name: "valueRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "Collection"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_string_builder_delete",
            parameters: [
                RuntimeABIParameter(name: "start", type: .intptr),
                RuntimeABIParameter(name: "end", type: .intptr),
            ],
            returnType: .intptr,
            section: "Collection"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_string_builder_length",
            parameters: [],
            returnType: .intptr,
            section: "Collection"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_builder_list_add",
            parameters: [
                RuntimeABIParameter(name: "elem", type: .intptr),
            ],
            returnType: .intptr,
            section: "Collection"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_builder_set_add",
            parameters: [
                RuntimeABIParameter(name: "elem", type: .intptr),
            ],
            returnType: .intptr,
            section: "Collection"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_list_getOrNull",
            parameters: [
                RuntimeABIParameter(name: "listRaw", type: .intptr),
                RuntimeABIParameter(name: "index", type: .intptr),
            ],
            returnType: .intptr,
            section: "Collection"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_list_elementAtOrNull",
            parameters: [
                RuntimeABIParameter(name: "listRaw", type: .intptr),
                RuntimeABIParameter(name: "index", type: .intptr),
            ],
            returnType: .intptr,
            section: "Collection"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_list_getOrElse",
            parameters: [
                RuntimeABIParameter(name: "listRaw", type: .intptr),
                RuntimeABIParameter(name: "index", type: .intptr),
                RuntimeABIParameter(name: "fnPtr", type: .intptr),
                RuntimeABIParameter(name: "closureRaw", type: .intptr),
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "Collection"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_list_firstOrNull",
            parameters: [
                RuntimeABIParameter(name: "listRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "Collection"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_list_lastOrNull",
            parameters: [
                RuntimeABIParameter(name: "listRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "Collection"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_mutable_list_add",
            parameters: [
                RuntimeABIParameter(name: "listRaw", type: .intptr),
                RuntimeABIParameter(name: "elem", type: .intptr),
            ],
            returnType: .intptr,
            section: "Collection"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_mutable_list_addAll",
            parameters: [
                RuntimeABIParameter(name: "listRaw", type: .intptr),
                RuntimeABIParameter(name: "collectionRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "Collection"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_mutable_list_removeAll",
            parameters: [
                RuntimeABIParameter(name: "listRaw", type: .intptr),
                RuntimeABIParameter(name: "collectionRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "Collection"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_mutable_list_retainAll",
            parameters: [
                RuntimeABIParameter(name: "listRaw", type: .intptr),
                RuntimeABIParameter(name: "collectionRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "Collection"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_mutable_list_removeAt",
            parameters: [
                RuntimeABIParameter(name: "listRaw", type: .intptr),
                RuntimeABIParameter(name: "index", type: .intptr),
            ],
            returnType: .intptr,
            section: "Collection"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_mutable_list_clear",
            parameters: [
                RuntimeABIParameter(name: "listRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "Collection"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_mutable_list_add_at",
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
            name: "kk_mutable_list_set",
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
            name: "kk_mutable_list_shuffle",
            parameters: [
                RuntimeABIParameter(name: "listRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "Collection"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_mutable_list_reverse",
            parameters: [
                RuntimeABIParameter(name: "listRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "Collection"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_mutable_set_add",
            parameters: [
                RuntimeABIParameter(name: "setRaw", type: .intptr),
                RuntimeABIParameter(name: "elem", type: .intptr),
            ],
            returnType: .intptr,
            section: "Collection"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_mutable_set_remove",
            parameters: [
                RuntimeABIParameter(name: "setRaw", type: .intptr),
                RuntimeABIParameter(name: "elem", type: .intptr),
            ],
            returnType: .intptr,
            section: "Collection"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_mutable_set_clear",
            parameters: [
                RuntimeABIParameter(name: "setRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "Collection"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_mutable_set_addAll",
            parameters: [
                RuntimeABIParameter(name: "setRaw", type: .intptr),
                RuntimeABIParameter(name: "collectionRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "Collection"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_builder_map_put",
            parameters: [
                RuntimeABIParameter(name: "key", type: .intptr),
                RuntimeABIParameter(name: "value", type: .intptr),
            ],
            returnType: .intptr,
            section: "Collection"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_mutable_map_put",
            parameters: [
                RuntimeABIParameter(name: "mapRaw", type: .intptr),
                RuntimeABIParameter(name: "key", type: .intptr),
                RuntimeABIParameter(name: "value", type: .intptr),
            ],
            returnType: .intptr,
            section: "Collection"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_mutable_map_remove",
            parameters: [
                RuntimeABIParameter(name: "mapRaw", type: .intptr),
                RuntimeABIParameter(name: "key", type: .intptr),
            ],
            returnType: .intptr,
            section: "Collection"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_mutable_map_clear",
            parameters: [
                RuntimeABIParameter(name: "mapRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "Collection"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_mutable_map_getOrPut",
            parameters: [
                RuntimeABIParameter(name: "mapRaw", type: .intptr),
                RuntimeABIParameter(name: "key", type: .intptr),
                RuntimeABIParameter(name: "fnPtr", type: .intptr),
                RuntimeABIParameter(name: "closureRaw", type: .intptr),
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "Collection"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_mutable_map_putAll",
            parameters: [
                RuntimeABIParameter(name: "mapRaw", type: .intptr),
                RuntimeABIParameter(name: "entriesRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "Collection"
        ),
    ]

    private static let hofLambdaParams: [RuntimeABIParameter] = [
        RuntimeABIParameter(name: "listRaw", type: .intptr),
        RuntimeABIParameter(name: "fnPtr", type: .intptr),
        RuntimeABIParameter(name: "closureRaw", type: .intptr),
        RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
    ]

    private static func hofSpec(_ name: String) -> RuntimeABIFunctionSpec {
        RuntimeABIFunctionSpec(
            name: name, parameters: hofLambdaParams,
            returnType: .intptr, section: "Collection"
        )
    }

    static let collectionHOFFunctions: [RuntimeABIFunctionSpec] = {
        let foldSpec = RuntimeABIFunctionSpec(
            name: "kk_list_fold",
            parameters: [
                RuntimeABIParameter(name: "listRaw", type: .intptr),
                RuntimeABIParameter(name: "initial", type: .intptr),
                RuntimeABIParameter(name: "fnPtr", type: .intptr),
                RuntimeABIParameter(name: "closureRaw", type: .intptr),
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "Collection"
        )
        let before = [
            "kk_list_map", "kk_list_filter", "kk_list_mapNotNull", "kk_list_forEach",
            "kk_list_flatMap", "kk_list_any", "kk_list_none", "kk_list_all",
        ]
        let reduceOrNullSpec = hofSpec("kk_list_reduceOrNull")
        let scanSpec = RuntimeABIFunctionSpec(
            name: "kk_list_scan",
            parameters: [
                RuntimeABIParameter(name: "listRaw", type: .intptr),
                RuntimeABIParameter(name: "initial", type: .intptr),
                RuntimeABIParameter(name: "fnPtr", type: .intptr),
                RuntimeABIParameter(name: "closureRaw", type: .intptr),
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "Collection"
        )
        let runningFoldSpec = RuntimeABIFunctionSpec(
            name: "kk_list_runningFold",
            parameters: [
                RuntimeABIParameter(name: "listRaw", type: .intptr),
                RuntimeABIParameter(name: "initial", type: .intptr),
                RuntimeABIParameter(name: "fnPtr", type: .intptr),
                RuntimeABIParameter(name: "closureRaw", type: .intptr),
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "Collection"
        )
        let runningReduceSpec = hofSpec("kk_list_runningReduce")
        let scanReduceSpec = hofSpec("kk_list_scanReduce")
        let genericAfter = [
            "kk_list_reduce", "kk_list_groupBy", "kk_list_sortedBy",
            "kk_list_count", "kk_list_first", "kk_list_last", "kk_list_find",
        ]
        let filterNotNullSpec = RuntimeABIFunctionSpec(
            name: "kk_list_filterNotNull",
            parameters: [
                RuntimeABIParameter(name: "listRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "Collection"
        )
        let associateBySpec = RuntimeABIFunctionSpec(
            name: "kk_list_associateBy",
            parameters: [
                RuntimeABIParameter(name: "listRaw", type: .intptr),
                RuntimeABIParameter(name: "fnPtr", type: .intptr),
                RuntimeABIParameter(name: "closureRaw", type: .intptr),
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "Collection"
        )
        let associateWithSpec = RuntimeABIFunctionSpec(
            name: "kk_list_associateWith",
            parameters: [
                RuntimeABIParameter(name: "listRaw", type: .intptr),
                RuntimeABIParameter(name: "fnPtr", type: .intptr),
                RuntimeABIParameter(name: "closureRaw", type: .intptr),
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "Collection"
        )
        let associateSpec = RuntimeABIFunctionSpec(
            name: "kk_list_associate",
            parameters: [
                RuntimeABIParameter(name: "listRaw", type: .intptr),
                RuntimeABIParameter(name: "fnPtr", type: .intptr),
                RuntimeABIParameter(name: "closureRaw", type: .intptr),
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "Collection"
        )
        let zipSpec = RuntimeABIFunctionSpec(
            name: "kk_list_zip",
            parameters: [
                RuntimeABIParameter(name: "listRaw", type: .intptr),
                RuntimeABIParameter(name: "otherRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "Collection"
        )
        let zipWithNextSpec = RuntimeABIFunctionSpec(
            name: "kk_list_zipWithNext",
            parameters: [
                RuntimeABIParameter(name: "listRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "Collection"
        )
        let zipWithNextTransformSpec = RuntimeABIFunctionSpec(
            name: "kk_list_zipWithNextTransform",
            parameters: [
                RuntimeABIParameter(name: "listRaw", type: .intptr),
                RuntimeABIParameter(name: "fnPtr", type: .intptr),
                RuntimeABIParameter(name: "closureRaw", type: .intptr),
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "Collection"
        )
        let unzipSpec = RuntimeABIFunctionSpec(
            name: "kk_list_unzip",
            parameters: [
                RuntimeABIParameter(name: "listRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "Collection"
        )
        let withIndexSpec = RuntimeABIFunctionSpec(
            name: "kk_list_withIndex",
            parameters: [
                RuntimeABIParameter(name: "listRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "Collection"
        )
        let forEachIndexedSpec = RuntimeABIFunctionSpec(
            name: "kk_list_forEachIndexed",
            parameters: [
                RuntimeABIParameter(name: "listRaw", type: .intptr),
                RuntimeABIParameter(name: "fnPtr", type: .intptr),
                RuntimeABIParameter(name: "closureRaw", type: .intptr),
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "Collection"
        )
        let mapIndexedSpec = RuntimeABIFunctionSpec(
            name: "kk_list_mapIndexed",
            parameters: [
                RuntimeABIParameter(name: "listRaw", type: .intptr),
                RuntimeABIParameter(name: "fnPtr", type: .intptr),
                RuntimeABIParameter(name: "closureRaw", type: .intptr),
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "Collection"
        )
        let sumOfSpec = RuntimeABIFunctionSpec(
            name: "kk_list_sumOf",
            parameters: [
                RuntimeABIParameter(name: "listRaw", type: .intptr),
                RuntimeABIParameter(name: "fnPtr", type: .intptr),
                RuntimeABIParameter(name: "closureRaw", type: .intptr),
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "Collection"
        )
        let maxOrNullSpec = RuntimeABIFunctionSpec(
            name: "kk_list_maxOrNull",
            parameters: [
                RuntimeABIParameter(name: "listRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "Collection"
        )
        let minOrNullSpec = RuntimeABIFunctionSpec(
            name: "kk_list_minOrNull",
            parameters: [
                RuntimeABIParameter(name: "listRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "Collection"
        )
        let takeSpec = RuntimeABIFunctionSpec(
            name: "kk_list_take",
            parameters: [
                RuntimeABIParameter(name: "listRaw", type: .intptr),
                RuntimeABIParameter(name: "count", type: .intptr),
            ],
            returnType: .intptr,
            section: "Collection"
        )
        let dropSpec = RuntimeABIFunctionSpec(
            name: "kk_list_drop",
            parameters: [
                RuntimeABIParameter(name: "listRaw", type: .intptr),
                RuntimeABIParameter(name: "count", type: .intptr),
            ],
            returnType: .intptr,
            section: "Collection"
        )
        let reversedSpec = RuntimeABIFunctionSpec(
            name: "kk_list_reversed",
            parameters: [
                RuntimeABIParameter(name: "listRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "Collection"
        )
        let asReversedSpec = RuntimeABIFunctionSpec(
            name: "kk_list_as_reversed",
            parameters: [
                RuntimeABIParameter(name: "listRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "Collection"
        )
        let sortedSpec = RuntimeABIFunctionSpec(
            name: "kk_list_sorted",
            parameters: [
                RuntimeABIParameter(name: "listRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "Collection"
        )
        let setSortedSpec = RuntimeABIFunctionSpec(
            name: "kk_set_sorted",
            parameters: [
                RuntimeABIParameter(name: "setRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "Collection"
        )
        let distinctSpec = RuntimeABIFunctionSpec(
            name: "kk_list_distinct",
            parameters: [
                RuntimeABIParameter(name: "listRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "Collection"
        )
        let shuffledSpec = RuntimeABIFunctionSpec(
            name: "kk_list_shuffled",
            parameters: [
                RuntimeABIParameter(name: "listRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "Collection"
        )
        let shuffledRandomSpec = RuntimeABIFunctionSpec(
            name: "kk_list_shuffled_random",
            parameters: [
                RuntimeABIParameter(name: "listRaw", type: .intptr),
                RuntimeABIParameter(name: "randomRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "Collection"
        )
        let randomSpec = RuntimeABIFunctionSpec(
            name: "kk_list_random",
            parameters: [
                RuntimeABIParameter(name: "listRaw", type: .intptr),
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "Collection"
        )
        let randomOrNullSpec = RuntimeABIFunctionSpec(
            name: "kk_list_randomOrNull",
            parameters: [
                RuntimeABIParameter(name: "listRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "Collection"
        )
        return before.map { hofSpec($0) }
            + [filterNotNullSpec, foldSpec]
            + genericAfter.map { hofSpec($0) }
            + [reduceOrNullSpec, scanSpec, runningFoldSpec, runningReduceSpec, scanReduceSpec]
            + [
                associateBySpec, associateWithSpec, associateSpec,
                RuntimeABIFunctionSpec(
                    name: "kk_list_associateByTo",
                    parameters: [
                        RuntimeABIParameter(name: "listRaw", type: .intptr),
                        RuntimeABIParameter(name: "destRaw", type: .intptr),
                        RuntimeABIParameter(name: "fnPtr", type: .intptr),
                        RuntimeABIParameter(name: "closureRaw", type: .intptr),
                        RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
                    ],
                    returnType: .intptr,
                    section: "Collection"
                ),
                RuntimeABIFunctionSpec(
                    name: "kk_list_associateWithTo",
                    parameters: [
                        RuntimeABIParameter(name: "listRaw", type: .intptr),
                        RuntimeABIParameter(name: "destRaw", type: .intptr),
                        RuntimeABIParameter(name: "fnPtr", type: .intptr),
                        RuntimeABIParameter(name: "closureRaw", type: .intptr),
                        RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
                    ],
                    returnType: .intptr,
                    section: "Collection"
                ),
                RuntimeABIFunctionSpec(
                    name: "kk_list_groupByTo",
                    parameters: [
                        RuntimeABIParameter(name: "listRaw", type: .intptr),
                        RuntimeABIParameter(name: "destRaw", type: .intptr),
                        RuntimeABIParameter(name: "fnPtr", type: .intptr),
                        RuntimeABIParameter(name: "closureRaw", type: .intptr),
                        RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
                    ],
                    returnType: .intptr,
                    section: "Collection"
                ),
                RuntimeABIFunctionSpec(
                    name: "kk_list_groupByTransform",
                    parameters: [
                        RuntimeABIParameter(name: "listRaw", type: .intptr),
                        RuntimeABIParameter(name: "keyFnPtr", type: .intptr),
                        RuntimeABIParameter(name: "keyClosureRaw", type: .intptr),
                        RuntimeABIParameter(name: "valueFnPtr", type: .intptr),
                        RuntimeABIParameter(name: "valueClosureRaw", type: .intptr),
                        RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
                    ],
                    returnType: .intptr,
                    section: "Collection"
                ),
                zipSpec, zipWithNextSpec, zipWithNextTransformSpec, unzipSpec, withIndexSpec, forEachIndexedSpec, mapIndexedSpec,
                hofSpec("kk_list_filterIndexed"),
                RuntimeABIFunctionSpec(name: "kk_list_foldIndexed", parameters: [RuntimeABIParameter(name: "listRaw", type: .intptr), RuntimeABIParameter(name: "initial", type: .intptr), RuntimeABIParameter(name: "fnPtr", type: .intptr), RuntimeABIParameter(name: "closureRaw", type: .intptr), RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer)], returnType: .intptr, section: "Collection"),
                hofSpec("kk_list_reduceIndexed"), hofSpec("kk_list_reduceIndexedOrNull"),
                RuntimeABIFunctionSpec(name: "kk_list_runningFoldIndexed", parameters: [RuntimeABIParameter(name: "listRaw", type: .intptr), RuntimeABIParameter(name: "initial", type: .intptr), RuntimeABIParameter(name: "fnPtr", type: .intptr), RuntimeABIParameter(name: "closureRaw", type: .intptr), RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer)], returnType: .intptr, section: "Collection"),
                hofSpec("kk_list_runningReduceIndexed"),
                RuntimeABIFunctionSpec(name: "kk_list_scanIndexed", parameters: [RuntimeABIParameter(name: "listRaw", type: .intptr), RuntimeABIParameter(name: "initial", type: .intptr), RuntimeABIParameter(name: "fnPtr", type: .intptr), RuntimeABIParameter(name: "closureRaw", type: .intptr), RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer)], returnType: .intptr, section: "Collection"),
                sumOfSpec, maxOrNullSpec, minOrNullSpec,
                takeSpec, dropSpec, reversedSpec, asReversedSpec, sortedSpec, setSortedSpec, distinctSpec,
                shuffledSpec, shuffledRandomSpec, randomSpec, randomOrNullSpec,
                RuntimeABIFunctionSpec(
                    name: "kk_list_flatten",
                    parameters: [
                        RuntimeABIParameter(name: "listRaw", type: .intptr),
                    ],
                    returnType: .intptr,
                    section: "Collection"
                ),
                RuntimeABIFunctionSpec(
                    name: "kk_list_indexOf",
                    parameters: [
                        RuntimeABIParameter(name: "listRaw", type: .intptr),
                        RuntimeABIParameter(name: "element", type: .intptr),
                    ],
                    returnType: .intptr,
                    section: "Collection"
                ),
                RuntimeABIFunctionSpec(
                    name: "kk_list_lastIndexOf",
                    parameters: [
                        RuntimeABIParameter(name: "listRaw", type: .intptr),
                        RuntimeABIParameter(name: "element", type: .intptr),
                    ],
                    returnType: .intptr,
                    section: "Collection"
                ),
                hofSpec("kk_list_binarySearch_compare"),
                hofSpec("kk_list_indexOfFirst"),
                hofSpec("kk_list_indexOfLast"),
                RuntimeABIFunctionSpec(
                    name: "kk_list_filterIsInstance",
                    parameters: [
                        RuntimeABIParameter(name: "listRaw", type: .intptr),
                        RuntimeABIParameter(name: "typeToken", type: .intptr),
                    ],
                    returnType: .intptr,
                    section: "Collection"
                ),
                RuntimeABIFunctionSpec(
                    name: "kk_list_chunked",
                    parameters: [
                        RuntimeABIParameter(name: "listRaw", type: .intptr),
                        RuntimeABIParameter(name: "size", type: .intptr),
                    ],
                    returnType: .intptr,
                    section: "Collection"
                ),
                RuntimeABIFunctionSpec(
                    name: "kk_list_chunked_transform",
                    parameters: [
                        RuntimeABIParameter(name: "listRaw", type: .intptr),
                        RuntimeABIParameter(name: "size", type: .intptr),
                        RuntimeABIParameter(name: "fnPtr", type: .intptr),
                        RuntimeABIParameter(name: "closureRaw", type: .intptr),
                        RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
                    ],
                    returnType: .intptr,
                    section: "Collection"
                ),
                RuntimeABIFunctionSpec(
                    name: "kk_list_windowed_default",
                    parameters: [
                        RuntimeABIParameter(name: "listRaw", type: .intptr),
                        RuntimeABIParameter(name: "size", type: .intptr),
                    ],
                    returnType: .intptr,
                    section: "Collection"
                ),
                RuntimeABIFunctionSpec(
                    name: "kk_list_windowed",
                    parameters: [
                        RuntimeABIParameter(name: "listRaw", type: .intptr),
                        RuntimeABIParameter(name: "size", type: .intptr),
                        RuntimeABIParameter(name: "step", type: .intptr),
                    ],
                    returnType: .intptr,
                    section: "Collection"
                ),
                RuntimeABIFunctionSpec(
                    name: "kk_list_windowed_partial",
                    parameters: [
                        RuntimeABIParameter(name: "listRaw", type: .intptr),
                        RuntimeABIParameter(name: "size", type: .intptr),
                        RuntimeABIParameter(name: "step", type: .intptr),
                        RuntimeABIParameter(name: "partialWindows", type: .intptr),
                    ],
                    returnType: .intptr,
                    section: "Collection"
                ),
                RuntimeABIFunctionSpec(
                    name: "kk_list_sortedDescending",
                    parameters: [
                        RuntimeABIParameter(name: "listRaw", type: .intptr),
                    ],
                    returnType: .intptr,
                    section: "Collection"
                ),
                hofSpec("kk_list_sortedByDescending"),
                hofSpec("kk_list_sortedWith"),
                hofSpec("kk_list_partition"),
                hofSpec("kk_list_takeWhile"),
                hofSpec("kk_list_dropWhile"),
                hofSpec("kk_list_takeLastWhile"),
                hofSpec("kk_list_dropLastWhile"),
                RuntimeABIFunctionSpec(
                    name: "kk_list_maxByOrNull",
                    parameters: [
                        RuntimeABIParameter(name: "listRaw", type: .intptr),
                        RuntimeABIParameter(name: "fnPtr", type: .intptr),
                        RuntimeABIParameter(name: "closureRaw", type: .intptr),
                        RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
                    ],
                    returnType: .intptr,
                    section: "Collection"
                ),
                RuntimeABIFunctionSpec(
                    name: "kk_list_minByOrNull",
                    parameters: [
                        RuntimeABIParameter(name: "listRaw", type: .intptr),
                        RuntimeABIParameter(name: "fnPtr", type: .intptr),
                        RuntimeABIParameter(name: "closureRaw", type: .intptr),
                        RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
                    ],
                    returnType: .intptr,
                    section: "Collection"
                ),
                RuntimeABIFunctionSpec(
                    name: "kk_list_maxOfOrNull",
                    parameters: [
                        RuntimeABIParameter(name: "listRaw", type: .intptr),
                        RuntimeABIParameter(name: "fnPtr", type: .intptr),
                        RuntimeABIParameter(name: "closureRaw", type: .intptr),
                        RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
                    ],
                    returnType: .intptr,
                    section: "Collection"
                ),
                RuntimeABIFunctionSpec(
                    name: "kk_list_minOfOrNull",
                    parameters: [
                        RuntimeABIParameter(name: "listRaw", type: .intptr),
                        RuntimeABIParameter(name: "fnPtr", type: .intptr),
                        RuntimeABIParameter(name: "closureRaw", type: .intptr),
                        RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
                    ],
                    returnType: .intptr,
                    section: "Collection"
                ),
                RuntimeABIFunctionSpec(
                    name: "kk_list_plus_element",
                    parameters: [
                        RuntimeABIParameter(name: "listRaw", type: .intptr),
                        RuntimeABIParameter(name: "element", type: .intptr),
                    ],
                    returnType: .intptr,
                    section: "Collection"
                ),
                RuntimeABIFunctionSpec(
                    name: "kk_list_plus_collection",
                    parameters: [
                        RuntimeABIParameter(name: "listRaw", type: .intptr),
                        RuntimeABIParameter(name: "otherList", type: .intptr),
                    ],
                    returnType: .intptr,
                    section: "Collection"
                ),
                RuntimeABIFunctionSpec(
                    name: "kk_list_minus_element",
                    parameters: [
                        RuntimeABIParameter(name: "listRaw", type: .intptr),
                        RuntimeABIParameter(name: "element", type: .intptr),
                    ],
                    returnType: .intptr,
                    section: "Collection"
                ),
                RuntimeABIFunctionSpec(
                    name: "kk_list_minus_collection",
                    parameters: [
                        RuntimeABIParameter(name: "listRaw", type: .intptr),
                        RuntimeABIParameter(name: "otherList", type: .intptr),
                    ],
                    returnType: .intptr,
                    section: "Collection"
                ),
                RuntimeABIFunctionSpec(
                    name: "kk_list_containsAll",
                    parameters: [
                        RuntimeABIParameter(name: "listRaw", type: .intptr),
                        RuntimeABIParameter(name: "otherListRaw", type: .intptr),
                    ],
                    returnType: .intptr,
                    section: "Collection"
                ),
                RuntimeABIFunctionSpec(
                    name: "kk_list_binarySearch",
                    parameters: [
                        RuntimeABIParameter(name: "listRaw", type: .intptr),
                        RuntimeABIParameter(name: "element", type: .intptr),
                    ],
                    returnType: .intptr,
                    section: "Collection"
                ),
                // ArrayDeque (STDLIB-240)
                RuntimeABIFunctionSpec(
                    name: "kk_arraydeque_new",
                    parameters: [],
                    returnType: .intptr,
                    section: "Collection"
                ),
                RuntimeABIFunctionSpec(
                    name: "kk_arraydeque_addFirst",
                    parameters: [
                        RuntimeABIParameter(name: "dequeRaw", type: .intptr),
                        RuntimeABIParameter(name: "element", type: .intptr),
                    ],
                    returnType: .intptr,
                    section: "Collection"
                ),
                RuntimeABIFunctionSpec(
                    name: "kk_arraydeque_addLast",
                    parameters: [
                        RuntimeABIParameter(name: "dequeRaw", type: .intptr),
                        RuntimeABIParameter(name: "element", type: .intptr),
                    ],
                    returnType: .intptr,
                    section: "Collection"
                ),
                RuntimeABIFunctionSpec(
                    name: "kk_arraydeque_removeFirst",
                    parameters: [
                        RuntimeABIParameter(name: "dequeRaw", type: .intptr),
                        RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
                    ],
                    returnType: .intptr,
                    section: "Collection"
                ),
                RuntimeABIFunctionSpec(
                    name: "kk_arraydeque_removeLast",
                    parameters: [
                        RuntimeABIParameter(name: "dequeRaw", type: .intptr),
                        RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
                    ],
                    returnType: .intptr,
                    section: "Collection"
                ),
                RuntimeABIFunctionSpec(
                    name: "kk_arraydeque_first",
                    parameters: [
                        RuntimeABIParameter(name: "dequeRaw", type: .intptr),
                        RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
                    ],
                    returnType: .intptr,
                    section: "Collection"
                ),
                RuntimeABIFunctionSpec(
                    name: "kk_arraydeque_last",
                    parameters: [
                        RuntimeABIParameter(name: "dequeRaw", type: .intptr),
                        RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
                    ],
                    returnType: .intptr,
                    section: "Collection"
                ),
                RuntimeABIFunctionSpec(
                    name: "kk_arraydeque_size",
                    parameters: [
                        RuntimeABIParameter(name: "dequeRaw", type: .intptr),
                    ],
                    returnType: .intptr,
                    section: "Collection"
                ),
                RuntimeABIFunctionSpec(
                    name: "kk_arraydeque_isEmpty",
                    parameters: [
                        RuntimeABIParameter(name: "dequeRaw", type: .intptr),
                    ],
                    returnType: .intptr,
                    section: "Collection"
                ),
                RuntimeABIFunctionSpec(
                    name: "kk_arraydeque_toString",
                    parameters: [
                        RuntimeABIParameter(name: "dequeRaw", type: .intptr),
                    ],
                    returnType: .opaquePointer,
                    section: "Collection"
                ),
                // Grouping (STDLIB-285/286)
                RuntimeABIFunctionSpec(
                    name: "kk_list_groupingBy",
                    parameters: [
                        RuntimeABIParameter(name: "listRaw", type: .intptr),
                        RuntimeABIParameter(name: "fnPtr", type: .intptr),
                        RuntimeABIParameter(name: "closureRaw", type: .intptr),
                    ],
                    returnType: .intptr,
                    section: "Collection"
                ),
                RuntimeABIFunctionSpec(
                    name: "kk_grouping_eachCount",
                    parameters: [
                        RuntimeABIParameter(name: "groupingRaw", type: .intptr),
                        RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
                    ],
                    returnType: .intptr,
                    section: "Collection"
                ),
                RuntimeABIFunctionSpec(
                    name: "kk_grouping_fold",
                    parameters: [
                        RuntimeABIParameter(name: "groupingRaw", type: .intptr),
                        RuntimeABIParameter(name: "initial", type: .intptr),
                        RuntimeABIParameter(name: "fnPtr", type: .intptr),
                        RuntimeABIParameter(name: "closureRaw", type: .intptr),
                        RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
                    ],
                    returnType: .intptr,
                    section: "Collection"
                ),
                RuntimeABIFunctionSpec(
                    name: "kk_grouping_reduce",
                    parameters: [
                        RuntimeABIParameter(name: "groupingRaw", type: .intptr),
                        RuntimeABIParameter(name: "fnPtr", type: .intptr),
                        RuntimeABIParameter(name: "closureRaw", type: .intptr),
                        RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
                    ],
                    returnType: .intptr,
                    section: "Collection"
                ),
                // STDLIB-250: Closeable.use {}
                RuntimeABIFunctionSpec(
                    name: "kk_use",
                    parameters: [
                        RuntimeABIParameter(name: "resourceRaw", type: .intptr),
                        RuntimeABIParameter(name: "fnPtr", type: .intptr),
                        RuntimeABIParameter(name: "closureRaw", type: .intptr),
                        RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
                    ],
                    returnType: .intptr,
                    section: "Collection"
                ),
                // STDLIB-533: List?.orEmpty()
                RuntimeABIFunctionSpec(
                    name: "kk_list_orEmpty",
                    parameters: [
                        RuntimeABIParameter(name: "listRaw", type: .intptr),
                    ],
                    returnType: .intptr,
                    section: "Collection"
                ),
                // STDLIB-532: Map?.orEmpty()
                RuntimeABIFunctionSpec(
                    name: "kk_map_orEmpty",
                    parameters: [
                        RuntimeABIParameter(name: "mapRaw", type: .intptr),
                    ],
                    returnType: .intptr,
                    section: "Collection"
                ),
            ]
    }()
}
