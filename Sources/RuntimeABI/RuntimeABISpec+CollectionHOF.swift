// swiftlint:disable file_length

/// `RuntimeABISpec.collectionHOFFunctions` extracted from
/// `RuntimeABISpec+Collection.swift`.
public extension RuntimeABISpec {
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
            "kk_list_flatMap", "kk_list_flatMapIndexed", "kk_list_any", "kk_list_none", "kk_list_all",
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
            "kk_list_count", "kk_list_first", "kk_list_last", "kk_list_find", "kk_list_findLast",
        ]
        let destinationLambdaParams = [
            RuntimeABIParameter(name: "listRaw", type: .intptr),
            RuntimeABIParameter(name: "destRaw", type: .intptr),
            RuntimeABIParameter(name: "fnPtr", type: .intptr),
            RuntimeABIParameter(name: "closureRaw", type: .intptr),
            RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
        ]
        let filterNotNullSpec = RuntimeABIFunctionSpec(
            name: "kk_list_filterNotNull",
            parameters: [
                RuntimeABIParameter(name: "listRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "Collection"
        )
        let requireNoNullsSpec = RuntimeABIFunctionSpec(
            name: "kk_iterable_requireNoNulls",
            parameters: [
                RuntimeABIParameter(name: "iterableRaw", type: .intptr),
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "Collection"
        )
        let filterNotNullToSpec = RuntimeABIFunctionSpec(
            name: "kk_list_filterNotNullTo",
            parameters: [
                RuntimeABIParameter(name: "listRaw", type: .intptr),
                RuntimeABIParameter(name: "destRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "Collection"
        )
        let filterIsInstanceToSpec = RuntimeABIFunctionSpec(
            name: "kk_list_filterIsInstanceTo",
            parameters: [
                RuntimeABIParameter(name: "listRaw", type: .intptr),
                RuntimeABIParameter(name: "destRaw", type: .intptr),
                RuntimeABIParameter(name: "typeToken", type: .intptr),
            ],
            returnType: .intptr,
            section: "Collection"
        )
        let filterToSpec = RuntimeABIFunctionSpec(
            name: "kk_list_filterTo",
            parameters: destinationLambdaParams,
            returnType: .intptr,
            section: "Collection"
        )
        let filterNotToSpec = RuntimeABIFunctionSpec(
            name: "kk_list_filterNotTo",
            parameters: destinationLambdaParams,
            returnType: .intptr,
            section: "Collection"
        )
        let mapToSpec = RuntimeABIFunctionSpec(
            name: "kk_list_mapTo",
            parameters: destinationLambdaParams,
            returnType: .intptr,
            section: "Collection"
        )
        let flatMapToSpec = RuntimeABIFunctionSpec(
            name: "kk_list_flatMapTo",
            parameters: destinationLambdaParams,
            returnType: .intptr,
            section: "Collection"
        )
        let mapNotNullToSpec = RuntimeABIFunctionSpec(
            name: "kk_list_mapNotNullTo",
            parameters: destinationLambdaParams,
            returnType: .intptr,
            section: "Collection"
        )
        let firstNotNullOfSpec = RuntimeABIFunctionSpec(
            name: "kk_iterable_firstNotNullOf",
            parameters: [
                RuntimeABIParameter(name: "iterableRaw", type: .intptr),
                RuntimeABIParameter(name: "fnPtr", type: .intptr),
                RuntimeABIParameter(name: "closureRaw", type: .intptr),
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "Collection"
        )
        let firstNotNullOfOrNullSpec = RuntimeABIFunctionSpec(
            name: "kk_iterable_firstNotNullOfOrNull",
            parameters: [
                RuntimeABIParameter(name: "iterableRaw", type: .intptr),
                RuntimeABIParameter(name: "fnPtr", type: .intptr),
                RuntimeABIParameter(name: "closureRaw", type: .intptr),
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "Collection"
        )
        let iterableAllSpec = RuntimeABIFunctionSpec(
            name: "kk_iterable_all",
            parameters: [
                RuntimeABIParameter(name: "iterableRaw", type: .intptr),
                RuntimeABIParameter(name: "fnPtr", type: .intptr),
                RuntimeABIParameter(name: "closureRaw", type: .intptr),
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "Collection"
        )
        let iterableLastSpec = RuntimeABIFunctionSpec(
            name: "kk_iterable_last",
            parameters: [
                RuntimeABIParameter(name: "iterableRaw", type: .intptr),
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "Collection"
        )
        let mapIndexedToSpec = RuntimeABIFunctionSpec(
            name: "kk_list_mapIndexedTo",
            parameters: destinationLambdaParams,
            returnType: .intptr,
            section: "Collection"
        )
        let mapIndexedNotNullToSpec = RuntimeABIFunctionSpec(
            name: "kk_list_mapIndexedNotNullTo",
            parameters: destinationLambdaParams,
            returnType: .intptr,
            section: "Collection"
        )
        let flatMapIndexedToSpec = RuntimeABIFunctionSpec(
            name: "kk_list_flatMapIndexedTo",
            parameters: destinationLambdaParams,
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
        let associateByTransformSpec = RuntimeABIFunctionSpec(
            name: "kk_list_associateByTransform",
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
        let associateToSpec = RuntimeABIFunctionSpec(
            name: "kk_list_associateTo",
            parameters: destinationLambdaParams,
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
        let mapIndexedNotNullSpec = RuntimeABIFunctionSpec(
            name: "kk_list_mapIndexedNotNull",
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
        let sumBySpec = RuntimeABIFunctionSpec(
            name: "kk_list_sumBy",
            parameters: [
                RuntimeABIParameter(name: "listRaw", type: .intptr),
                RuntimeABIParameter(name: "fnPtr", type: .intptr),
                RuntimeABIParameter(name: "closureRaw", type: .intptr),
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "Collection"
        )
        let sumByDoubleSpec = RuntimeABIFunctionSpec(
            name: "kk_list_sumByDouble",
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
        let maxSpec = RuntimeABIFunctionSpec(
            name: "kk_list_max",
            parameters: [
                RuntimeABIParameter(name: "listRaw", type: .intptr),
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "Collection"
        )
        let minSpec = RuntimeABIFunctionSpec(
            name: "kk_list_min",
            parameters: [
                RuntimeABIParameter(name: "listRaw", type: .intptr),
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "Collection"
        )
        let takeSpec = RuntimeABIFunctionSpec(
            name: "kk_list_take",
            parameters: [
                RuntimeABIParameter(name: "listRaw", type: .intptr),
                RuntimeABIParameter(name: "count", type: .intptr),
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
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
        let takeLastSpec = RuntimeABIFunctionSpec(
            name: "kk_list_takeLast",
            parameters: [
                RuntimeABIParameter(name: "listRaw", type: .intptr),
                RuntimeABIParameter(name: "count", type: .intptr),
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "Collection"
        )
        let sumSpec = RuntimeABIFunctionSpec(
            name: "kk_list_sum",
            parameters: [
                RuntimeABIParameter(name: "listRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "Collection"
        )
        let averageSpec = RuntimeABIFunctionSpec(
            name: "kk_list_average",
            parameters: [
                RuntimeABIParameter(name: "listRaw", type: .intptr),
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
        let sortedPrimitiveSpec = RuntimeABIFunctionSpec(
            name: "kk_list_sorted_primitive",
            parameters: [
                RuntimeABIParameter(name: "listRaw", type: .intptr),
                RuntimeABIParameter(name: "kindRaw", type: .int32),
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
        let sortedByPrimitiveSpec = RuntimeABIFunctionSpec(
            name: "kk_list_sortedBy_primitive",
            parameters: [
                RuntimeABIParameter(name: "listRaw", type: .intptr),
                RuntimeABIParameter(name: "fnPtr", type: .intptr),
                RuntimeABIParameter(name: "closureRaw", type: .intptr),
                RuntimeABIParameter(name: "kindRaw", type: .int32),
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "Collection"
        )
        return before.map { hofSpec($0) }
            + [filterNotNullSpec, requireNoNullsSpec, foldSpec]
            + [
                filterIsInstanceToSpec,
                filterToSpec, filterNotToSpec, mapToSpec, flatMapToSpec,
                mapNotNullToSpec, filterNotNullToSpec, firstNotNullOfSpec, firstNotNullOfOrNullSpec,
                iterableAllSpec, iterableLastSpec, mapIndexedToSpec, mapIndexedNotNullToSpec, flatMapIndexedToSpec,
            ]
            + genericAfter.flatMap { name in
                if name == "kk_list_sortedBy" {
                    return [hofSpec(name), sortedByPrimitiveSpec]
                }
                return [hofSpec(name)]
            }
            + [reduceOrNullSpec, scanSpec, runningFoldSpec, runningReduceSpec, scanReduceSpec]
            + [
                associateBySpec, associateByTransformSpec, associateWithSpec, associateSpec, associateToSpec,
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
                zipSpec, zipWithNextSpec, zipWithNextTransformSpec, unzipSpec, withIndexSpec, forEachIndexedSpec, mapIndexedSpec, mapIndexedNotNullSpec,
                sumOfSpec, sumBySpec, sumByDoubleSpec, maxOrNullSpec, minOrNullSpec,
                maxSpec, minSpec,
                takeSpec, dropSpec, takeLastSpec, sumSpec, averageSpec, reversedSpec, asReversedSpec, sortedSpec, distinctSpec,
                sortedPrimitiveSpec,
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
                RuntimeABIFunctionSpec(
                    name: "kk_list_binarySearchBy",
                    parameters: [
                        RuntimeABIParameter(name: "listRaw", type: .intptr),
                        RuntimeABIParameter(name: "key", type: .intptr),
                        RuntimeABIParameter(name: "fnPtr", type: .intptr),
                        RuntimeABIParameter(name: "closureRaw", type: .intptr),
                        RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
                    ],
                    returnType: .intptr,
                    section: "Collection"
                ),
                RuntimeABIFunctionSpec(
                    name: "kk_list_binarySearchBy_fromIndex",
                    parameters: [
                        RuntimeABIParameter(name: "listRaw", type: .intptr),
                        RuntimeABIParameter(name: "key", type: .intptr),
                        RuntimeABIParameter(name: "fromIndex", type: .intptr),
                        RuntimeABIParameter(name: "fnPtr", type: .intptr),
                        RuntimeABIParameter(name: "closureRaw", type: .intptr),
                        RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
                    ],
                    returnType: .intptr,
                    section: "Collection"
                ),
                RuntimeABIFunctionSpec(
                    name: "kk_list_binarySearchBy_range",
                    parameters: [
                        RuntimeABIParameter(name: "listRaw", type: .intptr),
                        RuntimeABIParameter(name: "key", type: .intptr),
                        RuntimeABIParameter(name: "fromIndex", type: .intptr),
                        RuntimeABIParameter(name: "toIndex", type: .intptr),
                        RuntimeABIParameter(name: "fnPtr", type: .intptr),
                        RuntimeABIParameter(name: "closureRaw", type: .intptr),
                        RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
                    ],
                    returnType: .intptr,
                    section: "Collection"
                ),
                hofSpec("kk_list_binarySearch_compare"),
                RuntimeABIFunctionSpec(
                    name: "kk_list_binarySearch_comparator",
                    parameters: [
                        RuntimeABIParameter(name: "listRaw", type: .intptr),
                        RuntimeABIParameter(name: "element", type: .intptr),
                        RuntimeABIParameter(name: "fnPtr", type: .intptr),
                        RuntimeABIParameter(name: "closureRaw", type: .intptr),
                        RuntimeABIParameter(name: "fromIndex", type: .intptr),
                        RuntimeABIParameter(name: "toIndex", type: .intptr),
                        RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
                    ],
                    returnType: .intptr,
                    section: "Collection"
                ),
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
                    name: "kk_list_windowed_transform",
                    parameters: [
                        RuntimeABIParameter(name: "listRaw", type: .intptr),
                        RuntimeABIParameter(name: "size", type: .intptr),
                        RuntimeABIParameter(name: "step", type: .intptr),
                        RuntimeABIParameter(name: "partialWindows", type: .intptr),
                        RuntimeABIParameter(name: "fnPtr", type: .intptr),
                        RuntimeABIParameter(name: "closureRaw", type: .intptr),
                        RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
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
                RuntimeABIFunctionSpec(
                    name: "kk_list_sortedDescending_primitive",
                    parameters: [
                        RuntimeABIParameter(name: "listRaw", type: .intptr),
                        RuntimeABIParameter(name: "kindRaw", type: .int32),
                    ],
                    returnType: .intptr,
                    section: "Collection"
                ),
                RuntimeABIFunctionSpec(
                    name: "kk_list_sortedByDescending",
                    parameters: hofLambdaParams,
                    returnType: .intptr,
                    section: "Collection"
                ),
                RuntimeABIFunctionSpec(
                    name: "kk_list_sortedByDescending_primitive",
                    parameters: [
                        RuntimeABIParameter(name: "listRaw", type: .intptr),
                        RuntimeABIParameter(name: "fnPtr", type: .intptr),
                        RuntimeABIParameter(name: "closureRaw", type: .intptr),
                        RuntimeABIParameter(name: "kindRaw", type: .int32),
                        RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
                    ],
                    returnType: .intptr,
                    section: "Collection"
                ),
                hofSpec("kk_list_sortedWith"),
                hofSpec("kk_list_partition"),
                hofSpec("kk_list_takeWhile"),
                hofSpec("kk_list_dropWhile"),
                hofSpec("kk_list_takeLastWhile"),
                hofSpec("kk_list_dropLastWhile"),
                RuntimeABIFunctionSpec(
                    name: "kk_list_maxBy",
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
                    name: "kk_list_minBy",
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
                // Array binarySearch overloads (TYPE-103)
                RuntimeABIFunctionSpec(
                    name: "kk_array_binarySearch",
                    parameters: [
                        RuntimeABIParameter(name: "arrayRaw", type: .intptr),
                        RuntimeABIParameter(name: "element", type: .intptr),
                        RuntimeABIParameter(name: "fromIndex", type: .intptr),
                        RuntimeABIParameter(name: "toIndex", type: .intptr),
                    ],
                    returnType: .intptr,
                    section: "Collection"
                ),
                RuntimeABIFunctionSpec(
                    name: "kk_intArray_binarySearch",
                    parameters: [
                        RuntimeABIParameter(name: "arrayRaw", type: .intptr),
                        RuntimeABIParameter(name: "element", type: .intptr),
                        RuntimeABIParameter(name: "fromIndex", type: .intptr),
                        RuntimeABIParameter(name: "toIndex", type: .intptr),
                    ],
                    returnType: .intptr,
                    section: "Collection"
                ),
                RuntimeABIFunctionSpec(
                    name: "kk_longArray_binarySearch",
                    parameters: [
                        RuntimeABIParameter(name: "arrayRaw", type: .intptr),
                        RuntimeABIParameter(name: "element", type: .intptr),
                        RuntimeABIParameter(name: "fromIndex", type: .intptr),
                        RuntimeABIParameter(name: "toIndex", type: .intptr),
                    ],
                    returnType: .intptr,
                    section: "Collection"
                ),
                RuntimeABIFunctionSpec(
                    name: "kk_byteArray_binarySearch",
                    parameters: [
                        RuntimeABIParameter(name: "arrayRaw", type: .intptr),
                        RuntimeABIParameter(name: "element", type: .intptr),
                        RuntimeABIParameter(name: "fromIndex", type: .intptr),
                        RuntimeABIParameter(name: "toIndex", type: .intptr),
                    ],
                    returnType: .intptr,
                    section: "Collection"
                ),
                RuntimeABIFunctionSpec(
                    name: "kk_shortArray_binarySearch",
                    parameters: [
                        RuntimeABIParameter(name: "arrayRaw", type: .intptr),
                        RuntimeABIParameter(name: "element", type: .intptr),
                        RuntimeABIParameter(name: "fromIndex", type: .intptr),
                        RuntimeABIParameter(name: "toIndex", type: .intptr),
                    ],
                    returnType: .intptr,
                    section: "Collection"
                ),
                RuntimeABIFunctionSpec(
                    name: "kk_uIntArray_binarySearch",
                    parameters: [
                        RuntimeABIParameter(name: "arrayRaw", type: .intptr),
                        RuntimeABIParameter(name: "element", type: .intptr),
                        RuntimeABIParameter(name: "fromIndex", type: .intptr),
                        RuntimeABIParameter(name: "toIndex", type: .intptr),
                    ],
                    returnType: .intptr,
                    section: "Collection"
                ),
                RuntimeABIFunctionSpec(
                    name: "kk_uLongArray_binarySearch",
                    parameters: [
                        RuntimeABIParameter(name: "arrayRaw", type: .intptr),
                        RuntimeABIParameter(name: "element", type: .intptr),
                        RuntimeABIParameter(name: "fromIndex", type: .intptr),
                        RuntimeABIParameter(name: "toIndex", type: .intptr),
                    ],
                    returnType: .intptr,
                    section: "Collection"
                ),
                RuntimeABIFunctionSpec(
                    name: "kk_doubleArray_binarySearch",
                    parameters: [
                        RuntimeABIParameter(name: "arrayRaw", type: .intptr),
                        RuntimeABIParameter(name: "element", type: .intptr),
                        RuntimeABIParameter(name: "fromIndex", type: .intptr),
                        RuntimeABIParameter(name: "toIndex", type: .intptr),
                    ],
                    returnType: .intptr,
                    section: "Collection"
                ),
                RuntimeABIFunctionSpec(
                    name: "kk_floatArray_binarySearch",
                    parameters: [
                        RuntimeABIParameter(name: "arrayRaw", type: .intptr),
                        RuntimeABIParameter(name: "element", type: .intptr),
                        RuntimeABIParameter(name: "fromIndex", type: .intptr),
                        RuntimeABIParameter(name: "toIndex", type: .intptr),
                    ],
                    returnType: .intptr,
                    section: "Collection"
                ),
                RuntimeABIFunctionSpec(
                    name: "kk_booleanArray_binarySearch",
                    parameters: [
                        RuntimeABIParameter(name: "arrayRaw", type: .intptr),
                        RuntimeABIParameter(name: "element", type: .intptr),
                        RuntimeABIParameter(name: "fromIndex", type: .intptr),
                        RuntimeABIParameter(name: "toIndex", type: .intptr),
                    ],
                    returnType: .intptr,
                    section: "Collection"
                ),
                RuntimeABIFunctionSpec(
                    name: "kk_charArray_binarySearch",
                    parameters: [
                        RuntimeABIParameter(name: "arrayRaw", type: .intptr),
                        RuntimeABIParameter(name: "element", type: .intptr),
                        RuntimeABIParameter(name: "fromIndex", type: .intptr),
                        RuntimeABIParameter(name: "toIndex", type: .intptr),
                    ],
                    returnType: .intptr,
                    section: "Collection"
                ),
                RuntimeABIFunctionSpec(
                    name: "kk_uByteArray_binarySearch",
                    parameters: [
                        RuntimeABIParameter(name: "arrayRaw", type: .intptr),
                        RuntimeABIParameter(name: "element", type: .intptr),
                        RuntimeABIParameter(name: "fromIndex", type: .intptr),
                        RuntimeABIParameter(name: "toIndex", type: .intptr),
                    ],
                    returnType: .intptr,
                    section: "Collection"
                ),
                RuntimeABIFunctionSpec(
                    name: "kk_uShortArray_binarySearch",
                    parameters: [
                        RuntimeABIParameter(name: "arrayRaw", type: .intptr),
                        RuntimeABIParameter(name: "element", type: .intptr),
                        RuntimeABIParameter(name: "fromIndex", type: .intptr),
                        RuntimeABIParameter(name: "toIndex", type: .intptr),
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
                    name: "kk_grouping_eachCountTo",
                    parameters: [
                        RuntimeABIParameter(name: "groupingRaw", type: .intptr),
                        RuntimeABIParameter(name: "destRaw", type: .intptr),
                        RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
                    ],
                    returnType: .intptr,
                    section: "Collection"
                ),
                RuntimeABIFunctionSpec(
                    name: "kk_grouping_aggregate",
                    parameters: [
                        RuntimeABIParameter(name: "groupingRaw", type: .intptr),
                        RuntimeABIParameter(name: "fnPtr", type: .intptr),
                        RuntimeABIParameter(name: "closureRaw", type: .intptr),
                        RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
                    ],
                    returnType: .intptr,
                    section: "Collection"
                ),
                RuntimeABIFunctionSpec(
                    name: "kk_grouping_aggregateTo",
                    parameters: [
                        RuntimeABIParameter(name: "groupingRaw", type: .intptr),
                        RuntimeABIParameter(name: "destRaw", type: .intptr),
                        RuntimeABIParameter(name: "fnPtr", type: .intptr),
                        RuntimeABIParameter(name: "closureRaw", type: .intptr),
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
                    name: "kk_grouping_fold_initialValueSelector",
                    parameters: [
                        RuntimeABIParameter(name: "groupingRaw", type: .intptr),
                        RuntimeABIParameter(name: "initialValueSelectorFnPtr", type: .intptr),
                        RuntimeABIParameter(name: "initialValueSelectorClosureRaw", type: .intptr),
                        RuntimeABIParameter(name: "operationFnPtr", type: .intptr),
                        RuntimeABIParameter(name: "operationClosureRaw", type: .intptr),
                        RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
                    ],
                    returnType: .intptr,
                    section: "Collection"
                ),
                RuntimeABIFunctionSpec(
                    name: "kk_grouping_foldTo",
                    parameters: [
                        RuntimeABIParameter(name: "groupingRaw", type: .intptr),
                        RuntimeABIParameter(name: "destinationRaw", type: .intptr),
                        RuntimeABIParameter(name: "initial", type: .intptr),
                        RuntimeABIParameter(name: "fnPtr", type: .intptr),
                        RuntimeABIParameter(name: "closureRaw", type: .intptr),
                        RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
                    ],
                    returnType: .intptr,
                    section: "Collection"
                ),
                RuntimeABIFunctionSpec(
                    name: "kk_grouping_foldTo_selector",
                    parameters: [
                        RuntimeABIParameter(name: "groupingRaw", type: .intptr),
                        RuntimeABIParameter(name: "destinationRaw", type: .intptr),
                        RuntimeABIParameter(name: "initialValueSelectorFnPtr", type: .intptr),
                        RuntimeABIParameter(name: "initialValueSelectorClosureRaw", type: .intptr),
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
                RuntimeABIFunctionSpec(
                    name: "kk_grouping_reduceTo",
                    parameters: [
                        RuntimeABIParameter(name: "groupingRaw", type: .intptr),
                        RuntimeABIParameter(name: "destRaw", type: .intptr),
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
                // STDLIB-KOTLIN-ROOT-CLOSE-001: AutoCloseable { closeAction }
                RuntimeABIFunctionSpec(
                    name: "kk_auto_closeable_create",
                    parameters: [
                        RuntimeABIParameter(name: "fnPtr", type: .intptr),
                        RuntimeABIParameter(name: "closureRaw", type: .intptr),
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
