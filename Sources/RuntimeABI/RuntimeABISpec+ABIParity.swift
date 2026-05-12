// Residual ABI parity specs that do not yet have a categorized RuntimeABISpec section.

public extension RuntimeABISpec {
    static let abiParityFunctions: [RuntimeABIFunctionSpec] = [
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
            name: "kk_kclass_register_annotation",
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
    ]
}
