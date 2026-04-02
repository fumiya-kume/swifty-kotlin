// Parallel processing ABI specs (STDLIB-PERF-155)

public extension RuntimeABISpec {
    static let parallelFunctions: [RuntimeABIFunctionSpec] = [
        RuntimeABIFunctionSpec(
            name: "kk_parallel_pool_new",
            parameters: [
                RuntimeABIParameter(name: "workerCount", type: .intptr),
            ],
            returnType: .intptr,
            section: "Parallel"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_parallel_stream_from_collection",
            parameters: [
                RuntimeABIParameter(name: "collectionRaw", type: .intptr),
                RuntimeABIParameter(name: "poolRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "Parallel"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_parallel_stream_to_list",
            parameters: [
                RuntimeABIParameter(name: "streamRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "Parallel"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_parallel_stream_map",
            parameters: [
                RuntimeABIParameter(name: "streamRaw", type: .intptr),
                RuntimeABIParameter(name: "fnPtr", type: .intptr),
                RuntimeABIParameter(name: "closureRaw", type: .intptr),
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "Parallel"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_parallel_stream_forEach",
            parameters: [
                RuntimeABIParameter(name: "streamRaw", type: .intptr),
                RuntimeABIParameter(name: "fnPtr", type: .intptr),
                RuntimeABIParameter(name: "closureRaw", type: .intptr),
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "Parallel"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_parallel_stream_reduce",
            parameters: [
                RuntimeABIParameter(name: "streamRaw", type: .intptr),
                RuntimeABIParameter(name: "initial", type: .intptr),
                RuntimeABIParameter(name: "fnPtr", type: .intptr),
                RuntimeABIParameter(name: "closureRaw", type: .intptr),
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "Parallel"
        ),
    ]
}
