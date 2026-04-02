// ThreadLocal (java.lang.ThreadLocal / kotlin.concurrent.getOrSet)

public extension RuntimeABIExterns {
    static let threadLocalExterns: [ExternDecl] = [
        kk_thread_local_new,
        kk_thread_local_getOrSet,
    ]

    static let kk_thread_local_new = ExternDecl(
        name: "kk_thread_local_new",
        parameterTypes: [],
        returnType: "intptr_t"
    )

    static let kk_thread_local_getOrSet = ExternDecl(
        name: "kk_thread_local_getOrSet",
        parameterTypes: ["intptr_t", "intptr_t", "intptr_t", "intptr_t * _Nullable"],
        returnType: "intptr_t"
    )
}
