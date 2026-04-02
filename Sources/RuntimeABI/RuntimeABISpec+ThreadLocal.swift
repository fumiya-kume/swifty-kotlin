// ThreadLocal (java.lang.ThreadLocal / kotlin.concurrent.getOrSet)

public extension RuntimeABISpec {
    static let threadLocalFunctions: [RuntimeABIFunctionSpec] = [
        RuntimeABIFunctionSpec(
            name: "kk_thread_local_new",
            parameters: [],
            returnType: .intptr,
            section: "ThreadLocal"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_thread_local_getOrSet",
            parameters: [
                RuntimeABIParameter(name: "receiver", type: .intptr),
                RuntimeABIParameter(name: "fnPtr", type: .intptr),
                RuntimeABIParameter(name: "closureRaw", type: .intptr),
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "ThreadLocal"
        ),
    ]
}
