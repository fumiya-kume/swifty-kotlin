public extension RuntimeABISpec {
    /// Memory-representation and worker-thread bridges retained for the
    /// source-backed kotlin.native.concurrent package functions (KSP-1216).
    static let nativeConcurrentFunctions: [RuntimeABIFunctionSpec] = [
        RuntimeABIFunctionSpec(
            name: "__kk_native_concurrent_attach_object_graph",
            parameters: [
                RuntimeABIParameter(name: "stableRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "NativeConcurrent",
            isThrowing: false
        ),
        RuntimeABIFunctionSpec(
            name: "__kk_native_concurrent_consume_future",
            parameters: [
                RuntimeABIParameter(name: "futureHandle", type: .intptr),
            ],
            returnType: .intptr,
            section: "NativeConcurrent",
            isThrowing: false
        ),
        RuntimeABIFunctionSpec(
            name: "__kk_native_concurrent_detach_object_graph",
            parameters: [
                RuntimeABIParameter(name: "modeRaw", type: .intptr),
                RuntimeABIParameter(name: "valueRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "NativeConcurrent",
            isThrowing: false
        ),
        RuntimeABIFunctionSpec(
            name: "__kk_native_concurrent_execute_impl",
            parameters: [
                RuntimeABIParameter(name: "workerHandle", type: .intptr),
                RuntimeABIParameter(name: "modeRaw", type: .intptr),
                RuntimeABIParameter(name: "jobArgumentRaw", type: .intptr),
                RuntimeABIParameter(name: "jobPointerHandle", type: .intptr),
            ],
            returnType: .intptr,
            section: "NativeConcurrent",
            isThrowing: false
        ),
        RuntimeABIFunctionSpec(
            name: "__kk_native_concurrent_start_worker",
            parameters: [
                RuntimeABIParameter(name: "errorReportingRaw", type: .intptr),
                RuntimeABIParameter(name: "nameRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "NativeConcurrent",
            isThrowing: false
        ),
        RuntimeABIFunctionSpec(
            name: "__kk_native_concurrent_terminate_worker",
            parameters: [
                RuntimeABIParameter(name: "workerHandle", type: .intptr),
            ],
            returnType: .intptr,
            section: "NativeConcurrent",
            isThrowing: false
        ),
        RuntimeABIFunctionSpec(
            name: "__kk_native_concurrent_wait_for_multiple_futures",
            parameters: [
                RuntimeABIParameter(name: "futuresHandle", type: .intptr),
                RuntimeABIParameter(name: "timeoutMillis", type: .intptr),
            ],
            returnType: .intptr,
            section: "NativeConcurrent",
            isThrowing: false
        ),
        RuntimeABIFunctionSpec(
            name: "__kk_native_concurrent_wait_worker_termination",
            parameters: [
                RuntimeABIParameter(name: "workerHandle", type: .intptr),
            ],
            returnType: .intptr,
            section: "NativeConcurrent",
            isThrowing: false
        ),
    ]
}
