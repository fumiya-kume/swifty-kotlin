// Thread (java.lang.Thread / kotlin.concurrent.thread)

public extension RuntimeABISpec {
    static let threadFunctions: [RuntimeABIFunctionSpec] = [
        RuntimeABIFunctionSpec(
            name: "kk_thread_create",
            parameters: [
                RuntimeABIParameter(name: "start", type: .intptr),
                RuntimeABIParameter(name: "isDaemon", type: .intptr),
                RuntimeABIParameter(name: "contextClassLoaderRaw", type: .intptr),
                RuntimeABIParameter(name: "nameRaw", type: .intptr),
                RuntimeABIParameter(name: "priority", type: .intptr),
                RuntimeABIParameter(name: "fnPtr", type: .intptr),
                RuntimeABIParameter(name: "closureRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "Thread"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_thread_sleep",
            parameters: [
                RuntimeABIParameter(name: "millis", type: .intptr),
            ],
            returnType: .intptr,
            section: "Thread"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_thread_currentThread",
            parameters: [],
            returnType: .intptr,
            section: "Thread"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_thread_join",
            parameters: [
                RuntimeABIParameter(name: "threadRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "Thread"
        ),
    ]
}
