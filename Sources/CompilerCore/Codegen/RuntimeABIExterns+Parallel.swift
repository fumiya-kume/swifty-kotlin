// MARK: - Parallel Extern Declarations (STDLIB-PERF-155)

public extension RuntimeABIExterns {
    static let parallelExterns: [ExternDecl] = [
        kk_parallel_pool_new,
        kk_parallel_stream_from_collection,
        kk_parallel_stream_to_list,
        kk_parallel_stream_map,
        kk_parallel_stream_forEach,
        kk_parallel_stream_reduce,
    ]

    static let kk_parallel_pool_new = ExternDecl(
        name: "kk_parallel_pool_new",
        parameterTypes: ["intptr_t"],
        returnType: "intptr_t"
    )

    static let kk_parallel_stream_from_collection = ExternDecl(
        name: "kk_parallel_stream_from_collection",
        parameterTypes: ["intptr_t", "intptr_t"],
        returnType: "intptr_t"
    )

    static let kk_parallel_stream_to_list = ExternDecl(
        name: "kk_parallel_stream_to_list",
        parameterTypes: ["intptr_t"],
        returnType: "intptr_t"
    )

    static let kk_parallel_stream_map = ExternDecl(
        name: "kk_parallel_stream_map",
        parameterTypes: ["intptr_t", "intptr_t", "intptr_t", "intptr_t * _Nullable"],
        returnType: "intptr_t"
    )

    static let kk_parallel_stream_forEach = ExternDecl(
        name: "kk_parallel_stream_forEach",
        parameterTypes: ["intptr_t", "intptr_t", "intptr_t", "intptr_t * _Nullable"],
        returnType: "intptr_t"
    )

    static let kk_parallel_stream_reduce = ExternDecl(
        name: "kk_parallel_stream_reduce",
        parameterTypes: ["intptr_t", "intptr_t", "intptr_t", "intptr_t", "intptr_t * _Nullable"],
        returnType: "intptr_t"
    )
}
