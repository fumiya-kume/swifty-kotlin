// Auto-generated ABI parity specs to reconcile RuntimeABISpec with RuntimeABIExterns.

public extension RuntimeABISpec {
    static let abiParityFunctionsPart1: [RuntimeABIFunctionSpec] = [
        RuntimeABIFunctionSpec(
            name: "kk_callable_ref_tag_kfunction",
            parameters: [
                RuntimeABIParameter(name: "p0", type: .intptr),
                RuntimeABIParameter(name: "p1", type: .intptr),
                RuntimeABIParameter(name: "p2", type: .intptr),
            ],
            returnType: .intptr,
            section: "ABIParity"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_callable_ref_tag_kproperty",
            parameters: [
                RuntimeABIParameter(name: "p0", type: .intptr),
                RuntimeABIParameter(name: "p1", type: .intptr),
                RuntimeABIParameter(name: "p2", type: .intptr),
            ],
            returnType: .intptr,
            section: "ABIParity"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_callable_ref_name",
            parameters: [
                RuntimeABIParameter(name: "p0", type: .intptr),
            ],
            returnType: .intptr,
            section: "ABIParity"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_list_of_not_null",
            parameters: [
                RuntimeABIParameter(name: "p0", type: .intptr),
                RuntimeABIParameter(name: "p1", type: .intptr),
            ],
            returnType: .intptr,
            section: "ABIParity"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_list_intersect",
            parameters: [
                RuntimeABIParameter(name: "p0", type: .intptr),
                RuntimeABIParameter(name: "p1", type: .intptr),
            ],
            returnType: .intptr,
            section: "ABIParity"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_list_union",
            parameters: [
                RuntimeABIParameter(name: "p0", type: .intptr),
                RuntimeABIParameter(name: "p1", type: .intptr),
            ],
            returnType: .intptr,
            section: "ABIParity"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_list_subtract",
            parameters: [
                RuntimeABIParameter(name: "p0", type: .intptr),
                RuntimeABIParameter(name: "p1", type: .intptr),
            ],
            returnType: .intptr,
            section: "ABIParity"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_list_toHashSet",
            parameters: [
                RuntimeABIParameter(name: "p0", type: .intptr),
            ],
            returnType: .intptr,
            section: "ABIParity"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_set_containsAll",
            parameters: [
                RuntimeABIParameter(name: "p0", type: .intptr),
                RuntimeABIParameter(name: "p1", type: .intptr),
            ],
            returnType: .intptr,
            section: "ABIParity"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_set_sorted",
            parameters: [
                RuntimeABIParameter(name: "p0", type: .intptr),
            ],
            returnType: .intptr,
            section: "ABIParity"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_set_sortedDescending",
            parameters: [
                RuntimeABIParameter(name: "p0", type: .intptr),
            ],
            returnType: .intptr,
            section: "ABIParity"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_collection_size",
            parameters: [
                RuntimeABIParameter(name: "p0", type: .intptr),
            ],
            returnType: .intptr,
            section: "ABIParity"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_collection_isEmpty",
            parameters: [
                RuntimeABIParameter(name: "p0", type: .intptr),
            ],
            returnType: .intptr,
            section: "ABIParity"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_map_flatMap",
            parameters: [
                RuntimeABIParameter(name: "p0", type: .intptr),
                RuntimeABIParameter(name: "p1", type: .intptr),
                RuntimeABIParameter(name: "p2", type: .intptr),
                RuntimeABIParameter(name: "p3", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "ABIParity"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_map_maxByOrNull",
            parameters: [
                RuntimeABIParameter(name: "p0", type: .intptr),
                RuntimeABIParameter(name: "p1", type: .intptr),
                RuntimeABIParameter(name: "p2", type: .intptr),
                RuntimeABIParameter(name: "p3", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "ABIParity"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_map_minByOrNull",
            parameters: [
                RuntimeABIParameter(name: "p0", type: .intptr),
                RuntimeABIParameter(name: "p1", type: .intptr),
                RuntimeABIParameter(name: "p2", type: .intptr),
                RuntimeABIParameter(name: "p3", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "ABIParity"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_array_mapIndexed",
            parameters: [
                RuntimeABIParameter(name: "p0", type: .intptr),
                RuntimeABIParameter(name: "p1", type: .intptr),
                RuntimeABIParameter(name: "p2", type: .intptr),
                RuntimeABIParameter(name: "p3", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "ABIParity"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_array_mapNotNull",
            parameters: [
                RuntimeABIParameter(name: "p0", type: .intptr),
                RuntimeABIParameter(name: "p1", type: .intptr),
                RuntimeABIParameter(name: "p2", type: .intptr),
                RuntimeABIParameter(name: "p3", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "ABIParity"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_array_flatMap",
            parameters: [
                RuntimeABIParameter(name: "p0", type: .intptr),
                RuntimeABIParameter(name: "p1", type: .intptr),
                RuntimeABIParameter(name: "p2", type: .intptr),
                RuntimeABIParameter(name: "p3", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "ABIParity"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_array_filterIndexed",
            parameters: [
                RuntimeABIParameter(name: "p0", type: .intptr),
                RuntimeABIParameter(name: "p1", type: .intptr),
                RuntimeABIParameter(name: "p2", type: .intptr),
                RuntimeABIParameter(name: "p3", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "ABIParity"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_array_filterNot",
            parameters: [
                RuntimeABIParameter(name: "p0", type: .intptr),
                RuntimeABIParameter(name: "p1", type: .intptr),
                RuntimeABIParameter(name: "p2", type: .intptr),
                RuntimeABIParameter(name: "p3", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "ABIParity"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_array_filterNotNull",
            parameters: [
                RuntimeABIParameter(name: "p0", type: .intptr),
            ],
            returnType: .intptr,
            section: "ABIParity"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_array_reduce",
            parameters: [
                RuntimeABIParameter(name: "p0", type: .intptr),
                RuntimeABIParameter(name: "p1", type: .intptr),
                RuntimeABIParameter(name: "p2", type: .intptr),
                RuntimeABIParameter(name: "p3", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "ABIParity"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_array_reduceIndexed",
            parameters: [
                RuntimeABIParameter(name: "p0", type: .intptr),
                RuntimeABIParameter(name: "p1", type: .intptr),
                RuntimeABIParameter(name: "p2", type: .intptr),
                RuntimeABIParameter(name: "p3", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "ABIParity"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_array_reduceOrNull",
            parameters: [
                RuntimeABIParameter(name: "p0", type: .intptr),
                RuntimeABIParameter(name: "p1", type: .intptr),
                RuntimeABIParameter(name: "p2", type: .intptr),
                RuntimeABIParameter(name: "p3", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "ABIParity"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_array_fold",
            parameters: [
                RuntimeABIParameter(name: "p0", type: .intptr),
                RuntimeABIParameter(name: "p1", type: .intptr),
                RuntimeABIParameter(name: "p2", type: .intptr),
                RuntimeABIParameter(name: "p3", type: .intptr),
                RuntimeABIParameter(name: "p4", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "ABIParity"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_array_foldIndexed",
            parameters: [
                RuntimeABIParameter(name: "p0", type: .intptr),
                RuntimeABIParameter(name: "p1", type: .intptr),
                RuntimeABIParameter(name: "p2", type: .intptr),
                RuntimeABIParameter(name: "p3", type: .intptr),
                RuntimeABIParameter(name: "p4", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "ABIParity"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_array_find",
            parameters: [
                RuntimeABIParameter(name: "p0", type: .intptr),
                RuntimeABIParameter(name: "p1", type: .intptr),
                RuntimeABIParameter(name: "p2", type: .intptr),
                RuntimeABIParameter(name: "p3", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "ABIParity"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_array_findLast",
            parameters: [
                RuntimeABIParameter(name: "p0", type: .intptr),
                RuntimeABIParameter(name: "p1", type: .intptr),
                RuntimeABIParameter(name: "p2", type: .intptr),
                RuntimeABIParameter(name: "p3", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "ABIParity"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_array_first",
            parameters: [
                RuntimeABIParameter(name: "p0", type: .intptr),
                RuntimeABIParameter(name: "p1", type: .intptr),
                RuntimeABIParameter(name: "p2", type: .intptr),
                RuntimeABIParameter(name: "p3", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "ABIParity"
        )
    ]

    static let abiParityFunctionsPart2: [RuntimeABIFunctionSpec] = [
        RuntimeABIFunctionSpec(
            name: "kk_array_firstOrNull",
            parameters: [
                RuntimeABIParameter(name: "p0", type: .intptr),
                RuntimeABIParameter(name: "p1", type: .intptr),
                RuntimeABIParameter(name: "p2", type: .intptr),
                RuntimeABIParameter(name: "p3", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "ABIParity"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_array_last",
            parameters: [
                RuntimeABIParameter(name: "p0", type: .intptr),
                RuntimeABIParameter(name: "p1", type: .intptr),
                RuntimeABIParameter(name: "p2", type: .intptr),
                RuntimeABIParameter(name: "p3", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "ABIParity"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_array_lastOrNull",
            parameters: [
                RuntimeABIParameter(name: "p0", type: .intptr),
                RuntimeABIParameter(name: "p1", type: .intptr),
                RuntimeABIParameter(name: "p2", type: .intptr),
                RuntimeABIParameter(name: "p3", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "ABIParity"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_array_all",
            parameters: [
                RuntimeABIParameter(name: "p0", type: .intptr),
                RuntimeABIParameter(name: "p1", type: .intptr),
                RuntimeABIParameter(name: "p2", type: .intptr),
                RuntimeABIParameter(name: "p3", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "ABIParity"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_array_count",
            parameters: [
                RuntimeABIParameter(name: "p0", type: .intptr),
                RuntimeABIParameter(name: "p1", type: .intptr),
                RuntimeABIParameter(name: "p2", type: .intptr),
                RuntimeABIParameter(name: "p3", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "ABIParity"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_iterable_asSequence",
            parameters: [
                RuntimeABIParameter(name: "p0", type: .intptr),
            ],
            returnType: .intptr,
            section: "ABIParity"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_list_map",
            parameters: [
                RuntimeABIParameter(name: "p0", type: .intptr),
                RuntimeABIParameter(name: "p1", type: .intptr),
                RuntimeABIParameter(name: "p2", type: .intptr),
                RuntimeABIParameter(name: "p3", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "ABIParity"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_list_filter",
            parameters: [
                RuntimeABIParameter(name: "p0", type: .intptr),
                RuntimeABIParameter(name: "p1", type: .intptr),
                RuntimeABIParameter(name: "p2", type: .intptr),
                RuntimeABIParameter(name: "p3", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "ABIParity"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_list_filterNot",
            parameters: [
                RuntimeABIParameter(name: "p0", type: .intptr),
                RuntimeABIParameter(name: "p1", type: .intptr),
                RuntimeABIParameter(name: "p2", type: .intptr),
                RuntimeABIParameter(name: "p3", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "ABIParity"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_list_mapNotNull",
            parameters: [
                RuntimeABIParameter(name: "p0", type: .intptr),
                RuntimeABIParameter(name: "p1", type: .intptr),
                RuntimeABIParameter(name: "p2", type: .intptr),
                RuntimeABIParameter(name: "p3", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "ABIParity"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_list_forEach",
            parameters: [
                RuntimeABIParameter(name: "p0", type: .intptr),
                RuntimeABIParameter(name: "p1", type: .intptr),
                RuntimeABIParameter(name: "p2", type: .intptr),
                RuntimeABIParameter(name: "p3", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "ABIParity"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_list_flatMap",
            parameters: [
                RuntimeABIParameter(name: "p0", type: .intptr),
                RuntimeABIParameter(name: "p1", type: .intptr),
                RuntimeABIParameter(name: "p2", type: .intptr),
                RuntimeABIParameter(name: "p3", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "ABIParity"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_list_any",
            parameters: [
                RuntimeABIParameter(name: "p0", type: .intptr),
                RuntimeABIParameter(name: "p1", type: .intptr),
                RuntimeABIParameter(name: "p2", type: .intptr),
                RuntimeABIParameter(name: "p3", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "ABIParity"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_list_none",
            parameters: [
                RuntimeABIParameter(name: "p0", type: .intptr),
                RuntimeABIParameter(name: "p1", type: .intptr),
                RuntimeABIParameter(name: "p2", type: .intptr),
                RuntimeABIParameter(name: "p3", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "ABIParity"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_list_all",
            parameters: [
                RuntimeABIParameter(name: "p0", type: .intptr),
                RuntimeABIParameter(name: "p1", type: .intptr),
                RuntimeABIParameter(name: "p2", type: .intptr),
                RuntimeABIParameter(name: "p3", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "ABIParity"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_list_reduce",
            parameters: [
                RuntimeABIParameter(name: "p0", type: .intptr),
                RuntimeABIParameter(name: "p1", type: .intptr),
                RuntimeABIParameter(name: "p2", type: .intptr),
                RuntimeABIParameter(name: "p3", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "ABIParity"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_list_reduceOrNull",
            parameters: [
                RuntimeABIParameter(name: "p0", type: .intptr),
                RuntimeABIParameter(name: "p1", type: .intptr),
                RuntimeABIParameter(name: "p2", type: .intptr),
                RuntimeABIParameter(name: "p3", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "ABIParity"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_list_runningReduce",
            parameters: [
                RuntimeABIParameter(name: "p0", type: .intptr),
                RuntimeABIParameter(name: "p1", type: .intptr),
                RuntimeABIParameter(name: "p2", type: .intptr),
                RuntimeABIParameter(name: "p3", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "ABIParity"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_list_scanReduce",
            parameters: [
                RuntimeABIParameter(name: "p0", type: .intptr),
                RuntimeABIParameter(name: "p1", type: .intptr),
                RuntimeABIParameter(name: "p2", type: .intptr),
                RuntimeABIParameter(name: "p3", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "ABIParity"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_list_groupBy",
            parameters: [
                RuntimeABIParameter(name: "p0", type: .intptr),
                RuntimeABIParameter(name: "p1", type: .intptr),
                RuntimeABIParameter(name: "p2", type: .intptr),
                RuntimeABIParameter(name: "p3", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "ABIParity"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_list_sortedBy",
            parameters: [
                RuntimeABIParameter(name: "p0", type: .intptr),
                RuntimeABIParameter(name: "p1", type: .intptr),
                RuntimeABIParameter(name: "p2", type: .intptr),
                RuntimeABIParameter(name: "p3", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "ABIParity"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_list_count",
            parameters: [
                RuntimeABIParameter(name: "p0", type: .intptr),
                RuntimeABIParameter(name: "p1", type: .intptr),
                RuntimeABIParameter(name: "p2", type: .intptr),
                RuntimeABIParameter(name: "p3", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "ABIParity"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_list_first",
            parameters: [
                RuntimeABIParameter(name: "p0", type: .intptr),
                RuntimeABIParameter(name: "p1", type: .intptr),
                RuntimeABIParameter(name: "p2", type: .intptr),
                RuntimeABIParameter(name: "p3", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "ABIParity"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_list_last",
            parameters: [
                RuntimeABIParameter(name: "p0", type: .intptr),
                RuntimeABIParameter(name: "p1", type: .intptr),
                RuntimeABIParameter(name: "p2", type: .intptr),
                RuntimeABIParameter(name: "p3", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "ABIParity"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_list_find",
            parameters: [
                RuntimeABIParameter(name: "p0", type: .intptr),
                RuntimeABIParameter(name: "p1", type: .intptr),
                RuntimeABIParameter(name: "p2", type: .intptr),
                RuntimeABIParameter(name: "p3", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "ABIParity"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_indexing_iterable_iterator",
            parameters: [
                RuntimeABIParameter(name: "p0", type: .intptr),
            ],
            returnType: .intptr,
            section: "ABIParity"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_indexing_iterable_hasNext",
            parameters: [
                RuntimeABIParameter(name: "p0", type: .intptr),
            ],
            returnType: .intptr,
            section: "ABIParity"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_indexing_iterable_next",
            parameters: [
                RuntimeABIParameter(name: "p0", type: .intptr),
            ],
            returnType: .intptr,
            section: "ABIParity"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_list_filterIndexed",
            parameters: [
                RuntimeABIParameter(name: "p0", type: .intptr),
                RuntimeABIParameter(name: "p1", type: .intptr),
                RuntimeABIParameter(name: "p2", type: .intptr),
                RuntimeABIParameter(name: "p3", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "ABIParity"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_list_foldIndexed",
            parameters: [
                RuntimeABIParameter(name: "p0", type: .intptr),
                RuntimeABIParameter(name: "p1", type: .intptr),
                RuntimeABIParameter(name: "p2", type: .intptr),
                RuntimeABIParameter(name: "p3", type: .intptr),
                RuntimeABIParameter(name: "p4", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "ABIParity"
        )
    ]

    static let abiParityFunctionsPart3: [RuntimeABIFunctionSpec] = [
        RuntimeABIFunctionSpec(
            name: "kk_list_reduceIndexed",
            parameters: [
                RuntimeABIParameter(name: "p0", type: .intptr),
                RuntimeABIParameter(name: "p1", type: .intptr),
                RuntimeABIParameter(name: "p2", type: .intptr),
                RuntimeABIParameter(name: "p3", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "ABIParity"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_list_reduceIndexedOrNull",
            parameters: [
                RuntimeABIParameter(name: "p0", type: .intptr),
                RuntimeABIParameter(name: "p1", type: .intptr),
                RuntimeABIParameter(name: "p2", type: .intptr),
                RuntimeABIParameter(name: "p3", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "ABIParity"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_list_runningFoldIndexed",
            parameters: [
                RuntimeABIParameter(name: "p0", type: .intptr),
                RuntimeABIParameter(name: "p1", type: .intptr),
                RuntimeABIParameter(name: "p2", type: .intptr),
                RuntimeABIParameter(name: "p3", type: .intptr),
                RuntimeABIParameter(name: "p4", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "ABIParity"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_list_runningReduceIndexed",
            parameters: [
                RuntimeABIParameter(name: "p0", type: .intptr),
                RuntimeABIParameter(name: "p1", type: .intptr),
                RuntimeABIParameter(name: "p2", type: .intptr),
                RuntimeABIParameter(name: "p3", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "ABIParity"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_list_scanIndexed",
            parameters: [
                RuntimeABIParameter(name: "p0", type: .intptr),
                RuntimeABIParameter(name: "p1", type: .intptr),
                RuntimeABIParameter(name: "p2", type: .intptr),
                RuntimeABIParameter(name: "p3", type: .intptr),
                RuntimeABIParameter(name: "p4", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "ABIParity"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_list_maxOf",
            parameters: [
                RuntimeABIParameter(name: "p0", type: .intptr),
                RuntimeABIParameter(name: "p1", type: .intptr),
                RuntimeABIParameter(name: "p2", type: .intptr),
                RuntimeABIParameter(name: "p3", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "ABIParity"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_list_minOf",
            parameters: [
                RuntimeABIParameter(name: "p0", type: .intptr),
                RuntimeABIParameter(name: "p1", type: .intptr),
                RuntimeABIParameter(name: "p2", type: .intptr),
                RuntimeABIParameter(name: "p3", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "ABIParity"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_list_maxWith",
            parameters: [
                RuntimeABIParameter(name: "p0", type: .intptr),
                RuntimeABIParameter(name: "p1", type: .intptr),
                RuntimeABIParameter(name: "p2", type: .intptr),
                RuntimeABIParameter(name: "p3", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "ABIParity"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_list_maxWithOrNull",
            parameters: [
                RuntimeABIParameter(name: "p0", type: .intptr),
                RuntimeABIParameter(name: "p1", type: .intptr),
                RuntimeABIParameter(name: "p2", type: .intptr),
                RuntimeABIParameter(name: "p3", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "ABIParity"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_list_minWith",
            parameters: [
                RuntimeABIParameter(name: "p0", type: .intptr),
                RuntimeABIParameter(name: "p1", type: .intptr),
                RuntimeABIParameter(name: "p2", type: .intptr),
                RuntimeABIParameter(name: "p3", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "ABIParity"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_list_minWithOrNull",
            parameters: [
                RuntimeABIParameter(name: "p0", type: .intptr),
                RuntimeABIParameter(name: "p1", type: .intptr),
                RuntimeABIParameter(name: "p2", type: .intptr),
                RuntimeABIParameter(name: "p3", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "ABIParity"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_list_maxOfWith",
            parameters: [
                RuntimeABIParameter(name: "p0", type: .intptr),
                RuntimeABIParameter(name: "p1", type: .intptr),
                RuntimeABIParameter(name: "p2", type: .intptr),
                RuntimeABIParameter(name: "p3", type: .intptr),
                RuntimeABIParameter(name: "p4", type: .intptr),
                RuntimeABIParameter(name: "p5", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "ABIParity"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_list_maxOfWithOrNull",
            parameters: [
                RuntimeABIParameter(name: "p0", type: .intptr),
                RuntimeABIParameter(name: "p1", type: .intptr),
                RuntimeABIParameter(name: "p2", type: .intptr),
                RuntimeABIParameter(name: "p3", type: .intptr),
                RuntimeABIParameter(name: "p4", type: .intptr),
                RuntimeABIParameter(name: "p5", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "ABIParity"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_list_minOfWith",
            parameters: [
                RuntimeABIParameter(name: "p0", type: .intptr),
                RuntimeABIParameter(name: "p1", type: .intptr),
                RuntimeABIParameter(name: "p2", type: .intptr),
                RuntimeABIParameter(name: "p3", type: .intptr),
                RuntimeABIParameter(name: "p4", type: .intptr),
                RuntimeABIParameter(name: "p5", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "ABIParity"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_list_minOfWithOrNull",
            parameters: [
                RuntimeABIParameter(name: "p0", type: .intptr),
                RuntimeABIParameter(name: "p1", type: .intptr),
                RuntimeABIParameter(name: "p2", type: .intptr),
                RuntimeABIParameter(name: "p3", type: .intptr),
                RuntimeABIParameter(name: "p4", type: .intptr),
                RuntimeABIParameter(name: "p5", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "ABIParity"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_list_distinctBy",
            parameters: [
                RuntimeABIParameter(name: "p0", type: .intptr),
                RuntimeABIParameter(name: "p1", type: .intptr),
                RuntimeABIParameter(name: "p2", type: .intptr),
                RuntimeABIParameter(name: "p3", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "ABIParity"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_list_indexOfFirst",
            parameters: [
                RuntimeABIParameter(name: "p0", type: .intptr),
                RuntimeABIParameter(name: "p1", type: .intptr),
                RuntimeABIParameter(name: "p2", type: .intptr),
                RuntimeABIParameter(name: "p3", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "ABIParity"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_list_indexOfLast",
            parameters: [
                RuntimeABIParameter(name: "p0", type: .intptr),
                RuntimeABIParameter(name: "p1", type: .intptr),
                RuntimeABIParameter(name: "p2", type: .intptr),
                RuntimeABIParameter(name: "p3", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "ABIParity"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_list_sortedByDescending",
            parameters: [
                RuntimeABIParameter(name: "p0", type: .intptr),
                RuntimeABIParameter(name: "p1", type: .intptr),
                RuntimeABIParameter(name: "p2", type: .intptr),
                RuntimeABIParameter(name: "p3", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "ABIParity"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_list_sortedWith",
            parameters: [
                RuntimeABIParameter(name: "p0", type: .intptr),
                RuntimeABIParameter(name: "p1", type: .intptr),
                RuntimeABIParameter(name: "p2", type: .intptr),
                RuntimeABIParameter(name: "p3", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "ABIParity"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_list_partition",
            parameters: [
                RuntimeABIParameter(name: "p0", type: .intptr),
                RuntimeABIParameter(name: "p1", type: .intptr),
                RuntimeABIParameter(name: "p2", type: .intptr),
                RuntimeABIParameter(name: "p3", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "ABIParity"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_list_onEach",
            parameters: [
                RuntimeABIParameter(name: "p0", type: .intptr),
                RuntimeABIParameter(name: "p1", type: .intptr),
                RuntimeABIParameter(name: "p2", type: .intptr),
                RuntimeABIParameter(name: "p3", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "ABIParity"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_list_onEachIndexed",
            parameters: [
                RuntimeABIParameter(name: "p0", type: .intptr),
                RuntimeABIParameter(name: "p1", type: .intptr),
                RuntimeABIParameter(name: "p2", type: .intptr),
                RuntimeABIParameter(name: "p3", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "ABIParity"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_list_takeWhile",
            parameters: [
                RuntimeABIParameter(name: "p0", type: .intptr),
                RuntimeABIParameter(name: "p1", type: .intptr),
                RuntimeABIParameter(name: "p2", type: .intptr),
                RuntimeABIParameter(name: "p3", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "ABIParity"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_list_dropWhile",
            parameters: [
                RuntimeABIParameter(name: "p0", type: .intptr),
                RuntimeABIParameter(name: "p1", type: .intptr),
                RuntimeABIParameter(name: "p2", type: .intptr),
                RuntimeABIParameter(name: "p3", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "ABIParity"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_list_takeLastWhile",
            parameters: [
                RuntimeABIParameter(name: "p0", type: .intptr),
                RuntimeABIParameter(name: "p1", type: .intptr),
                RuntimeABIParameter(name: "p2", type: .intptr),
                RuntimeABIParameter(name: "p3", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "ABIParity"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_list_dropLastWhile",
            parameters: [
                RuntimeABIParameter(name: "p0", type: .intptr),
                RuntimeABIParameter(name: "p1", type: .intptr),
                RuntimeABIParameter(name: "p2", type: .intptr),
                RuntimeABIParameter(name: "p3", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "ABIParity"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_list_single",
            parameters: [
                RuntimeABIParameter(name: "p0", type: .intptr),
                RuntimeABIParameter(name: "p1", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "ABIParity"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_list_singleOrNull",
            parameters: [
                RuntimeABIParameter(name: "p0", type: .intptr),
            ],
            returnType: .intptr,
            section: "ABIParity"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_list_binarySearch_compare",
            parameters: [
                RuntimeABIParameter(name: "p0", type: .intptr),
                RuntimeABIParameter(name: "p1", type: .intptr),
                RuntimeABIParameter(name: "p2", type: .intptr),
                RuntimeABIParameter(name: "p3", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "ABIParity"
        )
    ]

    static let abiParityFunctionsPart4: [RuntimeABIFunctionSpec] = [
        RuntimeABIFunctionSpec(
            name: "kk_mutable_list_sort",
            parameters: [
                RuntimeABIParameter(name: "p0", type: .intptr),
            ],
            returnType: .intptr,
            section: "ABIParity"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_mutable_list_sortBy",
            parameters: [
                RuntimeABIParameter(name: "p0", type: .intptr),
                RuntimeABIParameter(name: "p1", type: .intptr),
                RuntimeABIParameter(name: "p2", type: .intptr),
                RuntimeABIParameter(name: "p3", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "ABIParity"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_mutable_list_sortByDescending",
            parameters: [
                RuntimeABIParameter(name: "p0", type: .intptr),
                RuntimeABIParameter(name: "p1", type: .intptr),
                RuntimeABIParameter(name: "p2", type: .intptr),
                RuntimeABIParameter(name: "p3", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "ABIParity"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_compareValues",
            parameters: [
                RuntimeABIParameter(name: "p0", type: .intptr),
                RuntimeABIParameter(name: "p1", type: .intptr),
                RuntimeABIParameter(name: "p2", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "ABIParity"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_compareValuesBy1",
            parameters: [
                RuntimeABIParameter(name: "p0", type: .intptr),
                RuntimeABIParameter(name: "p1", type: .intptr),
                RuntimeABIParameter(name: "p2", type: .intptr),
                RuntimeABIParameter(name: "p3", type: .intptr),
                RuntimeABIParameter(name: "p4", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "ABIParity"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_compareValuesBy",
            parameters: [
                RuntimeABIParameter(name: "p0", type: .intptr),
                RuntimeABIParameter(name: "p1", type: .intptr),
                RuntimeABIParameter(name: "p2", type: .intptr),
                RuntimeABIParameter(name: "p3", type: .intptr),
                RuntimeABIParameter(name: "p4", type: .intptr),
                RuntimeABIParameter(name: "p5", type: .intptr),
                RuntimeABIParameter(name: "p6", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "ABIParity"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_compareValuesBy3",
            parameters: [
                RuntimeABIParameter(name: "p0", type: .intptr),
                RuntimeABIParameter(name: "p1", type: .intptr),
                RuntimeABIParameter(name: "p2", type: .intptr),
                RuntimeABIParameter(name: "p3", type: .intptr),
                RuntimeABIParameter(name: "p4", type: .intptr),
                RuntimeABIParameter(name: "p5", type: .intptr),
                RuntimeABIParameter(name: "p6", type: .intptr),
                RuntimeABIParameter(name: "p7", type: .intptr),
                RuntimeABIParameter(name: "p8", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "ABIParity"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_kfunction_create",
            parameters: [
                RuntimeABIParameter(name: "p0", type: .intptr),
                RuntimeABIParameter(name: "p1", type: .intptr),
                RuntimeABIParameter(name: "p2", type: .intptr),
                RuntimeABIParameter(name: "p3", type: .intptr),
                RuntimeABIParameter(name: "p4", type: .intptr),
                RuntimeABIParameter(name: "p5", type: .intptr),
            ],
            returnType: .intptr,
            section: "ABIParity"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_kfunction_get_name",
            parameters: [
                RuntimeABIParameter(name: "p0", type: .intptr),
            ],
            returnType: .intptr,
            section: "ABIParity"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_kfunction_get_arity",
            parameters: [
                RuntimeABIParameter(name: "p0", type: .intptr),
            ],
            returnType: .intptr,
            section: "ABIParity"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_kfunction_get_return_type",
            parameters: [
                RuntimeABIParameter(name: "p0", type: .intptr),
            ],
            returnType: .intptr,
            section: "ABIParity"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_kfunction_is_suspend",
            parameters: [
                RuntimeABIParameter(name: "p0", type: .intptr),
            ],
            returnType: .intptr,
            section: "ABIParity"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_kfunction_get_parameters",
            parameters: [
                RuntimeABIParameter(name: "p0", type: .intptr),
            ],
            returnType: .intptr,
            section: "ABIParity"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_kfunction_call_0",
            parameters: [
                RuntimeABIParameter(name: "p0", type: .intptr),
                RuntimeABIParameter(name: "p1", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "ABIParity"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_kfunction_call_1",
            parameters: [
                RuntimeABIParameter(name: "p0", type: .intptr),
                RuntimeABIParameter(name: "p1", type: .intptr),
                RuntimeABIParameter(name: "p2", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "ABIParity"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_kfunction_call_2",
            parameters: [
                RuntimeABIParameter(name: "p0", type: .intptr),
                RuntimeABIParameter(name: "p1", type: .intptr),
                RuntimeABIParameter(name: "p2", type: .intptr),
                RuntimeABIParameter(name: "p3", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "ABIParity"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_kfunction_call_3",
            parameters: [
                RuntimeABIParameter(name: "p0", type: .intptr),
                RuntimeABIParameter(name: "p1", type: .intptr),
                RuntimeABIParameter(name: "p2", type: .intptr),
                RuntimeABIParameter(name: "p3", type: .intptr),
                RuntimeABIParameter(name: "p4", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "ABIParity"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_kfunction_call_vararg",
            parameters: [
                RuntimeABIParameter(name: "p0", type: .intptr),
                RuntimeABIParameter(name: "p1", type: .intptr),
                RuntimeABIParameter(name: "p2", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "ABIParity"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_double_isNaN",
            parameters: [
                RuntimeABIParameter(name: "p0", type: .intptr),
            ],
            returnType: .intptr,
            section: "ABIParity"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_double_isInfinite",
            parameters: [
                RuntimeABIParameter(name: "p0", type: .intptr),
            ],
            returnType: .intptr,
            section: "ABIParity"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_double_isFinite",
            parameters: [
                RuntimeABIParameter(name: "p0", type: .intptr),
            ],
            returnType: .intptr,
            section: "ABIParity"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_float_isNaN",
            parameters: [
                RuntimeABIParameter(name: "p0", type: .intptr),
            ],
            returnType: .intptr,
            section: "ABIParity"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_float_isInfinite",
            parameters: [
                RuntimeABIParameter(name: "p0", type: .intptr),
            ],
            returnType: .intptr,
            section: "ABIParity"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_float_isFinite",
            parameters: [
                RuntimeABIParameter(name: "p0", type: .intptr),
            ],
            returnType: .intptr,
            section: "ABIParity"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_double_toBits",
            parameters: [
                RuntimeABIParameter(name: "p0", type: .intptr),
            ],
            returnType: .intptr,
            section: "ABIParity"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_double_toRawBits",
            parameters: [
                RuntimeABIParameter(name: "p0", type: .intptr),
            ],
            returnType: .intptr,
            section: "ABIParity"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_double_fromBits",
            parameters: [
                RuntimeABIParameter(name: "p0", type: .intptr),
            ],
            returnType: .intptr,
            section: "ABIParity"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_float_toBits",
            parameters: [
                RuntimeABIParameter(name: "p0", type: .intptr),
            ],
            returnType: .intptr,
            section: "ABIParity"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_float_toRawBits",
            parameters: [
                RuntimeABIParameter(name: "p0", type: .intptr),
            ],
            returnType: .intptr,
            section: "ABIParity"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_float_fromBits",
            parameters: [
                RuntimeABIParameter(name: "p0", type: .intptr),
            ],
            returnType: .intptr,
            section: "ABIParity"
        )
    ]

    static let abiParityFunctionsPart5: [RuntimeABIFunctionSpec] = [
        RuntimeABIFunctionSpec(
            name: "kk_path_new",
            parameters: [
                RuntimeABIParameter(name: "p0", type: .intptr),
            ],
            returnType: .intptr,
            section: "ABIParity"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_path_name",
            parameters: [
                RuntimeABIParameter(name: "p0", type: .intptr),
            ],
            returnType: .intptr,
            section: "ABIParity"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_path_parent",
            parameters: [
                RuntimeABIParameter(name: "p0", type: .intptr),
            ],
            returnType: .intptr,
            section: "ABIParity"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_path_toString",
            parameters: [
                RuntimeABIParameter(name: "p0", type: .intptr),
            ],
            returnType: .intptr,
            section: "ABIParity"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_path_resolve_string",
            parameters: [
                RuntimeABIParameter(name: "p0", type: .intptr),
                RuntimeABIParameter(name: "p1", type: .intptr),
            ],
            returnType: .intptr,
            section: "ABIParity"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_path_resolve_path",
            parameters: [
                RuntimeABIParameter(name: "p0", type: .intptr),
                RuntimeABIParameter(name: "p1", type: .intptr),
            ],
            returnType: .intptr,
            section: "ABIParity"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_path_exists",
            parameters: [
                RuntimeABIParameter(name: "p0", type: .intptr),
            ],
            returnType: .intptr,
            section: "ABIParity"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_path_isDirectory",
            parameters: [
                RuntimeABIParameter(name: "p0", type: .intptr),
            ],
            returnType: .intptr,
            section: "ABIParity"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_path_isRegularFile",
            parameters: [
                RuntimeABIParameter(name: "p0", type: .intptr),
            ],
            returnType: .intptr,
            section: "ABIParity"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_path_readText",
            parameters: [
                RuntimeABIParameter(name: "p0", type: .intptr),
                RuntimeABIParameter(name: "p1", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "ABIParity"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_path_writeText",
            parameters: [
                RuntimeABIParameter(name: "p0", type: .intptr),
                RuntimeABIParameter(name: "p1", type: .intptr),
                RuntimeABIParameter(name: "p2", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "ABIParity"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_path_readLines",
            parameters: [
                RuntimeABIParameter(name: "p0", type: .intptr),
                RuntimeABIParameter(name: "p1", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "ABIParity"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_path_createDirectories",
            parameters: [
                RuntimeABIParameter(name: "p0", type: .intptr),
                RuntimeABIParameter(name: "p1", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "ABIParity"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_path_deleteIfExists",
            parameters: [
                RuntimeABIParameter(name: "p0", type: .intptr),
            ],
            returnType: .intptr,
            section: "ABIParity"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_path_listDirectoryEntries",
            parameters: [
                RuntimeABIParameter(name: "p0", type: .intptr),
                RuntimeABIParameter(name: "p1", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "ABIParity"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_result_mapCatching",
            parameters: [
                RuntimeABIParameter(name: "p0", type: .intptr),
                RuntimeABIParameter(name: "p1", type: .intptr),
                RuntimeABIParameter(name: "p2", type: .intptr),
                RuntimeABIParameter(name: "p3", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "ABIParity"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_result_flatMap",
            parameters: [
                RuntimeABIParameter(name: "p0", type: .intptr),
                RuntimeABIParameter(name: "p1", type: .intptr),
                RuntimeABIParameter(name: "p2", type: .intptr),
                RuntimeABIParameter(name: "p3", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "ABIParity"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_result_flatMapCatching",
            parameters: [
                RuntimeABIParameter(name: "p0", type: .intptr),
                RuntimeABIParameter(name: "p1", type: .intptr),
                RuntimeABIParameter(name: "p2", type: .intptr),
                RuntimeABIParameter(name: "p3", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "ABIParity"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_result_recoverCatching",
            parameters: [
                RuntimeABIParameter(name: "p0", type: .intptr),
                RuntimeABIParameter(name: "p1", type: .intptr),
                RuntimeABIParameter(name: "p2", type: .intptr),
                RuntimeABIParameter(name: "p3", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "ABIParity"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_result_component1",
            parameters: [
                RuntimeABIParameter(name: "p0", type: .intptr),
            ],
            returnType: .intptr,
            section: "ABIParity"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_result_component2",
            parameters: [
                RuntimeABIParameter(name: "p0", type: .intptr),
            ],
            returnType: .intptr,
            section: "ABIParity"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_sequence_takeWhile",
            parameters: [
                RuntimeABIParameter(name: "p0", type: .intptr),
                RuntimeABIParameter(name: "p1", type: .intptr),
                RuntimeABIParameter(name: "p2", type: .intptr),
            ],
            returnType: .intptr,
            section: "ABIParity"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_sequence_dropWhile",
            parameters: [
                RuntimeABIParameter(name: "p0", type: .intptr),
                RuntimeABIParameter(name: "p1", type: .intptr),
                RuntimeABIParameter(name: "p2", type: .intptr),
            ],
            returnType: .intptr,
            section: "ABIParity"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_sequence_filterNot",
            parameters: [
                RuntimeABIParameter(name: "p0", type: .intptr),
                RuntimeABIParameter(name: "p1", type: .intptr),
                RuntimeABIParameter(name: "p2", type: .intptr),
            ],
            returnType: .intptr,
            section: "ABIParity"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_sequence_find",
            parameters: [
                RuntimeABIParameter(name: "p0", type: .intptr),
                RuntimeABIParameter(name: "p1", type: .intptr),
                RuntimeABIParameter(name: "p2", type: .intptr),
                RuntimeABIParameter(name: "p3", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "ABIParity"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_sequence_asIterable",
            parameters: [
                RuntimeABIParameter(name: "p0", type: .intptr),
            ],
            returnType: .intptr,
            section: "ABIParity"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_measureTimedValue",
            parameters: [
                RuntimeABIParameter(name: "p0", type: .intptr),
                RuntimeABIParameter(name: "p1", type: .intptr),
                RuntimeABIParameter(name: "p2", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "ABIParity"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_timedvalue_new",
            parameters: [
                RuntimeABIParameter(name: "p0", type: .intptr),
                RuntimeABIParameter(name: "p1", type: .intptr),
            ],
            returnType: .intptr,
            section: "ABIParity"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_timedvalue_value",
            parameters: [
                RuntimeABIParameter(name: "p0", type: .intptr),
            ],
            returnType: .intptr,
            section: "ABIParity"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_timedvalue_duration",
            parameters: [
                RuntimeABIParameter(name: "p0", type: .intptr),
            ],
            returnType: .intptr,
            section: "ABIParity"
        )
    ]

    static let abiParityFunctionsPart6: [RuntimeABIFunctionSpec] = [
        RuntimeABIFunctionSpec(
            name: "kk_timedvalue_toString",
            parameters: [
                RuntimeABIParameter(name: "p0", type: .intptr),
            ],
            returnType: .intptr,
            section: "ABIParity"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_duration_absoluteValue",
            parameters: [
                RuntimeABIParameter(name: "p0", type: .intptr),
            ],
            returnType: .intptr,
            section: "ABIParity"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_instant_now",
            parameters: [

            ],
            returnType: .intptr,
            section: "ABIParity"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_instant_from_epoch_millis",
            parameters: [
                RuntimeABIParameter(name: "p0", type: .intptr),
            ],
            returnType: .intptr,
            section: "ABIParity"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_instant_elapsed",
            parameters: [
                RuntimeABIParameter(name: "p0", type: .intptr),
            ],
            returnType: .intptr,
            section: "ABIParity"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_duration_isNegative",
            parameters: [
                RuntimeABIParameter(name: "p0", type: .intptr),
            ],
            returnType: .intptr,
            section: "ABIParity"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_instant_epoch_seconds",
            parameters: [
                RuntimeABIParameter(name: "p0", type: .intptr),
            ],
            returnType: .intptr,
            section: "ABIParity"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_duration_isPositive",
            parameters: [
                RuntimeABIParameter(name: "p0", type: .intptr),
            ],
            returnType: .intptr,
            section: "ABIParity"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_instant_nano_of_second",
            parameters: [
                RuntimeABIParameter(name: "p0", type: .intptr),
            ],
            returnType: .intptr,
            section: "ABIParity"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_duration_isInfinite",
            parameters: [
                RuntimeABIParameter(name: "p0", type: .intptr),
            ],
            returnType: .intptr,
            section: "ABIParity"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_duration_isFinite",
            parameters: [
                RuntimeABIParameter(name: "p0", type: .intptr),
            ],
            returnType: .intptr,
            section: "ABIParity"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_duration_plus",
            parameters: [
                RuntimeABIParameter(name: "p0", type: .intptr),
                RuntimeABIParameter(name: "p1", type: .intptr),
            ],
            returnType: .intptr,
            section: "ABIParity"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_instant_plus_duration",
            parameters: [
                RuntimeABIParameter(name: "p0", type: .intptr),
                RuntimeABIParameter(name: "p1", type: .intptr),
            ],
            returnType: .intptr,
            section: "ABIParity"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_duration_minus",
            parameters: [
                RuntimeABIParameter(name: "p0", type: .intptr),
                RuntimeABIParameter(name: "p1", type: .intptr),
            ],
            returnType: .intptr,
            section: "ABIParity"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_instant_minus_duration",
            parameters: [
                RuntimeABIParameter(name: "p0", type: .intptr),
                RuntimeABIParameter(name: "p1", type: .intptr),
            ],
            returnType: .intptr,
            section: "ABIParity"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_duration_times_int",
            parameters: [
                RuntimeABIParameter(name: "p0", type: .intptr),
                RuntimeABIParameter(name: "p1", type: .intptr),
            ],
            returnType: .intptr,
            section: "ABIParity"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_instant_compare",
            parameters: [
                RuntimeABIParameter(name: "p0", type: .intptr),
                RuntimeABIParameter(name: "p1", type: .intptr),
            ],
            returnType: .intptr,
            section: "ABIParity"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_duration_div_int",
            parameters: [
                RuntimeABIParameter(name: "p0", type: .intptr),
                RuntimeABIParameter(name: "p1", type: .intptr),
            ],
            returnType: .intptr,
            section: "ABIParity"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_duration_unary_minus",
            parameters: [
                RuntimeABIParameter(name: "p0", type: .intptr),
            ],
            returnType: .intptr,
            section: "ABIParity"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_duration_compareTo",
            parameters: [
                RuntimeABIParameter(name: "p0", type: .intptr),
                RuntimeABIParameter(name: "p1", type: .intptr),
            ],
            returnType: .intptr,
            section: "ABIParity"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_instant_until",
            parameters: [
                RuntimeABIParameter(name: "p0", type: .intptr),
                RuntimeABIParameter(name: "p1", type: .intptr),
            ],
            returnType: .intptr,
            section: "ABIParity"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_instant_to_java_instant",
            parameters: [
                RuntimeABIParameter(name: "p0", type: .intptr),
            ],
            returnType: .intptr,
            section: "ABIParity"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_java_instant_to_kotlin_instant",
            parameters: [
                RuntimeABIParameter(name: "p0", type: .intptr),
            ],
            returnType: .intptr,
            section: "ABIParity"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_duration_to_java_duration",
            parameters: [
                RuntimeABIParameter(name: "p0", type: .intptr),
            ],
            returnType: .intptr,
            section: "ABIParity"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_java_duration_to_kotlin_duration",
            parameters: [
                RuntimeABIParameter(name: "p0", type: .intptr),
            ],
            returnType: .intptr,
            section: "ABIParity"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_instant_to_js_date",
            parameters: [
                RuntimeABIParameter(name: "p0", type: .intptr),
            ],
            returnType: .intptr,
            section: "ABIParity"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_js_date_to_kotlin_instant",
            parameters: [
                RuntimeABIParameter(name: "p0", type: .intptr),
            ],
            returnType: .intptr,
            section: "ABIParity"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_time_source_mark_now",
            parameters: [
                RuntimeABIParameter(name: "p0", type: .intptr),
            ],
            returnType: .intptr,
            section: "ABIParity"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_time_source_monotonic_mark_now",
            parameters: [
                RuntimeABIParameter(name: "p0", type: .intptr),
            ],
            returnType: .intptr,
            section: "ABIParity"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_time_mark_elapsed_now",
            parameters: [
                RuntimeABIParameter(name: "p0", type: .intptr),
            ],
            returnType: .intptr,
            section: "ABIParity"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_time_mark_has_passed_now",
            parameters: [
                RuntimeABIParameter(name: "p0", type: .intptr),
            ],
            returnType: .intptr,
            section: "ABIParity"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_time_mark_has_not_passed_now",
            parameters: [
                RuntimeABIParameter(name: "p0", type: .intptr),
            ],
            returnType: .intptr,
            section: "ABIParity"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_time_mark_plus_duration",
            parameters: [
                RuntimeABIParameter(name: "p0", type: .intptr),
                RuntimeABIParameter(name: "p1", type: .intptr),
            ],
            returnType: .intptr,
            section: "ABIParity"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_time_mark_minus_duration",
            parameters: [
                RuntimeABIParameter(name: "p0", type: .intptr),
                RuntimeABIParameter(name: "p1", type: .intptr),
            ],
            returnType: .intptr,
            section: "ABIParity"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_time_mark_minus_mark",
            parameters: [
                RuntimeABIParameter(name: "p0", type: .intptr),
                RuntimeABIParameter(name: "p1", type: .intptr),
            ],
            returnType: .intptr,
            section: "ABIParity"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_time_mark_compare",
            parameters: [
                RuntimeABIParameter(name: "p0", type: .intptr),
                RuntimeABIParameter(name: "p1", type: .intptr),
            ],
            returnType: .intptr,
            section: "ABIParity"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_string_singleOrNull",
            parameters: [
                RuntimeABIParameter(name: "p0", type: .intptr),
            ],
            returnType: .intptr,
            section: "ABIParity"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_string_substringAfter",
            parameters: [
                RuntimeABIParameter(name: "p0", type: .intptr),
                RuntimeABIParameter(name: "p1", type: .intptr),
            ],
            returnType: .intptr,
            section: "ABIParity"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_kclass_register_annotation",
            parameters: [
                RuntimeABIParameter(name: "p0", type: .intptr),
                RuntimeABIParameter(name: "p1", type: .intptr),
            ],
            returnType: .intptr,
            section: "ABIParity"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_kclass_get_annotations",
            parameters: [
                RuntimeABIParameter(name: "p0", type: .intptr),
            ],
            returnType: .intptr,
            section: "ABIParity"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_kclass_find_annotation",
            parameters: [
                RuntimeABIParameter(name: "p0", type: .intptr),
                RuntimeABIParameter(name: "p1", type: .intptr),
            ],
            returnType: .intptr,
            section: "ABIParity"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_kclass_has_annotation",
            parameters: [
                RuntimeABIParameter(name: "p0", type: .intptr),
                RuntimeABIParameter(name: "p1", type: .intptr),
            ],
            returnType: .intptr,
            section: "ABIParity"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_annotation_class_name",
            parameters: [
                RuntimeABIParameter(name: "p0", type: .intptr),
            ],
            returnType: .intptr,
            section: "ABIParity"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_annotation_simple_class_name",
            parameters: [
                RuntimeABIParameter(name: "p0", type: .intptr),
            ],
            returnType: .intptr,
            section: "ABIParity"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_annotation_get_arguments",
            parameters: [
                RuntimeABIParameter(name: "p0", type: .intptr),
            ],
            returnType: .intptr,
            section: "ABIParity"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_ulong_range_contains",
            parameters: [
                RuntimeABIParameter(name: "p0", type: .intptr),
                RuntimeABIParameter(name: "p1", type: .intptr),
            ],
            returnType: .intptr,
            section: "ABIParity"
        )
    ]

    static let abiParityFunctionsPart7: [RuntimeABIFunctionSpec] = [
        RuntimeABIFunctionSpec(
            name: "kk_ulong_range_first",
            parameters: [
                RuntimeABIParameter(name: "p0", type: .intptr),
            ],
            returnType: .intptr,
            section: "ABIParity"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_ulong_range_last",
            parameters: [
                RuntimeABIParameter(name: "p0", type: .intptr),
            ],
            returnType: .intptr,
            section: "ABIParity"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_ulong_range_step",
            parameters: [
                RuntimeABIParameter(name: "p0", type: .intptr),
            ],
            returnType: .intptr,
            section: "ABIParity"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_ulong_range_isEmpty",
            parameters: [
                RuntimeABIParameter(name: "p0", type: .intptr),
            ],
            returnType: .intptr,
            section: "ABIParity"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_ulong_range_toULongArray",
            parameters: [
                RuntimeABIParameter(name: "p0", type: .intptr),
            ],
            returnType: .intptr,
            section: "ABIParity"
        )
    ]

    static let abiParityFunctions: [RuntimeABIFunctionSpec] = abiParityFunctionsPart1 + abiParityFunctionsPart2 + abiParityFunctionsPart3 + abiParityFunctionsPart4 + abiParityFunctionsPart5 + abiParityFunctionsPart6 + abiParityFunctionsPart7
}
