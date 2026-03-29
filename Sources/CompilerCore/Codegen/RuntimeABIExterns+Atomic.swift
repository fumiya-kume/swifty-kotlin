// MARK: - Atomic (kotlin.concurrent.AtomicInt / AtomicLong / AtomicReference)

public extension RuntimeABIExterns {
    static let atomicExterns: [ExternDecl] = [
        // AtomicInt
        kk_atomic_int_create,
        kk_atomic_int_load,
        kk_atomic_int_store,
        kk_atomic_int_exchange,
        kk_atomic_int_compareAndSet,
        kk_atomic_int_compareAndExchange,
        kk_atomic_int_fetchAndAdd,
        kk_atomic_int_addAndFetch,
        kk_atomic_int_fetchAndIncrement,
        kk_atomic_int_incrementAndFetch,
        kk_atomic_int_decrementAndFetch,
        kk_atomic_int_getAndUpdate,
        kk_atomic_int_updateAndGet,
        // AtomicLong
        kk_atomic_long_create,
        kk_atomic_long_load,
        kk_atomic_long_store,
        kk_atomic_long_exchange,
        kk_atomic_long_compareAndSet,
        kk_atomic_long_compareAndExchange,
        kk_atomic_long_fetchAndAdd,
        kk_atomic_long_addAndFetch,
        kk_atomic_long_fetchAndIncrement,
        kk_atomic_long_incrementAndFetch,
        kk_atomic_long_decrementAndFetch,
        kk_atomic_long_getAndUpdate,
        kk_atomic_long_updateAndGet,
        // AtomicReference
        kk_atomic_ref_create,
        kk_atomic_ref_load,
        kk_atomic_ref_store,
        kk_atomic_ref_exchange,
        kk_atomic_ref_compareAndSet,
        kk_atomic_ref_compareAndExchange,
        // AtomicBool
        kk_atomic_bool_create,
        kk_atomic_bool_load,
        kk_atomic_bool_store,
        kk_atomic_bool_exchange,
        kk_atomic_bool_compareAndSet,
        kk_atomic_bool_compareAndExchange,
    ]

    // MARK: - AtomicInt

    static let kk_atomic_int_create = ExternDecl(
        name: "kk_atomic_int_create",
        parameterTypes: ["intptr_t"],
        returnType: "intptr_t"
    )

    static let kk_atomic_int_load = ExternDecl(
        name: "kk_atomic_int_load",
        parameterTypes: ["intptr_t"],
        returnType: "intptr_t"
    )

    static let kk_atomic_int_store = ExternDecl(
        name: "kk_atomic_int_store",
        parameterTypes: ["intptr_t", "intptr_t"],
        returnType: "intptr_t"
    )

    static let kk_atomic_int_exchange = ExternDecl(
        name: "kk_atomic_int_exchange",
        parameterTypes: ["intptr_t", "intptr_t"],
        returnType: "intptr_t"
    )

    static let kk_atomic_int_compareAndSet = ExternDecl(
        name: "kk_atomic_int_compareAndSet",
        parameterTypes: ["intptr_t", "intptr_t", "intptr_t"],
        returnType: "intptr_t"
    )

    static let kk_atomic_int_compareAndExchange = ExternDecl(
        name: "kk_atomic_int_compareAndExchange",
        parameterTypes: ["intptr_t", "intptr_t", "intptr_t"],
        returnType: "intptr_t"
    )

    static let kk_atomic_int_fetchAndAdd = ExternDecl(
        name: "kk_atomic_int_fetchAndAdd",
        parameterTypes: ["intptr_t", "intptr_t"],
        returnType: "intptr_t"
    )

    static let kk_atomic_int_addAndFetch = ExternDecl(
        name: "kk_atomic_int_addAndFetch",
        parameterTypes: ["intptr_t", "intptr_t"],
        returnType: "intptr_t"
    )

    static let kk_atomic_int_fetchAndIncrement = ExternDecl(
        name: "kk_atomic_int_fetchAndIncrement",
        parameterTypes: ["intptr_t"],
        returnType: "intptr_t"
    )

    static let kk_atomic_int_incrementAndFetch = ExternDecl(
        name: "kk_atomic_int_incrementAndFetch",
        parameterTypes: ["intptr_t"],
        returnType: "intptr_t"
    )

    static let kk_atomic_int_decrementAndFetch = ExternDecl(
        name: "kk_atomic_int_decrementAndFetch",
        parameterTypes: ["intptr_t"],
        returnType: "intptr_t"
    )

    static let kk_atomic_int_getAndUpdate = ExternDecl(
        name: "kk_atomic_int_getAndUpdate",
        parameterTypes: ["intptr_t", "intptr_t"],
        returnType: "intptr_t"
    )

    static let kk_atomic_int_updateAndGet = ExternDecl(
        name: "kk_atomic_int_updateAndGet",
        parameterTypes: ["intptr_t", "intptr_t"],
        returnType: "intptr_t"
    )

    // MARK: - AtomicLong

    static let kk_atomic_long_create = ExternDecl(
        name: "kk_atomic_long_create",
        parameterTypes: ["intptr_t"],
        returnType: "intptr_t"
    )

    static let kk_atomic_long_load = ExternDecl(
        name: "kk_atomic_long_load",
        parameterTypes: ["intptr_t"],
        returnType: "intptr_t"
    )

    static let kk_atomic_long_store = ExternDecl(
        name: "kk_atomic_long_store",
        parameterTypes: ["intptr_t", "intptr_t"],
        returnType: "intptr_t"
    )

    static let kk_atomic_long_exchange = ExternDecl(
        name: "kk_atomic_long_exchange",
        parameterTypes: ["intptr_t", "intptr_t"],
        returnType: "intptr_t"
    )

    static let kk_atomic_long_compareAndSet = ExternDecl(
        name: "kk_atomic_long_compareAndSet",
        parameterTypes: ["intptr_t", "intptr_t", "intptr_t"],
        returnType: "intptr_t"
    )

    static let kk_atomic_long_compareAndExchange = ExternDecl(
        name: "kk_atomic_long_compareAndExchange",
        parameterTypes: ["intptr_t", "intptr_t", "intptr_t"],
        returnType: "intptr_t"
    )

    static let kk_atomic_long_fetchAndAdd = ExternDecl(
        name: "kk_atomic_long_fetchAndAdd",
        parameterTypes: ["intptr_t", "intptr_t"],
        returnType: "intptr_t"
    )

    static let kk_atomic_long_addAndFetch = ExternDecl(
        name: "kk_atomic_long_addAndFetch",
        parameterTypes: ["intptr_t", "intptr_t"],
        returnType: "intptr_t"
    )

    static let kk_atomic_long_fetchAndIncrement = ExternDecl(
        name: "kk_atomic_long_fetchAndIncrement",
        parameterTypes: ["intptr_t"],
        returnType: "intptr_t"
    )

    static let kk_atomic_long_incrementAndFetch = ExternDecl(
        name: "kk_atomic_long_incrementAndFetch",
        parameterTypes: ["intptr_t"],
        returnType: "intptr_t"
    )

    static let kk_atomic_long_decrementAndFetch = ExternDecl(
        name: "kk_atomic_long_decrementAndFetch",
        parameterTypes: ["intptr_t"],
        returnType: "intptr_t"
    )

    static let kk_atomic_long_getAndUpdate = ExternDecl(
        name: "kk_atomic_long_getAndUpdate",
        parameterTypes: ["intptr_t", "intptr_t"],
        returnType: "intptr_t"
    )

    static let kk_atomic_long_updateAndGet = ExternDecl(
        name: "kk_atomic_long_updateAndGet",
        parameterTypes: ["intptr_t", "intptr_t"],
        returnType: "intptr_t"
    )

    // MARK: - AtomicReference

    static let kk_atomic_ref_create = ExternDecl(
        name: "kk_atomic_ref_create",
        parameterTypes: ["intptr_t"],
        returnType: "intptr_t"
    )

    static let kk_atomic_ref_load = ExternDecl(
        name: "kk_atomic_ref_load",
        parameterTypes: ["intptr_t"],
        returnType: "intptr_t"
    )

    static let kk_atomic_ref_store = ExternDecl(
        name: "kk_atomic_ref_store",
        parameterTypes: ["intptr_t", "intptr_t"],
        returnType: "intptr_t"
    )

    static let kk_atomic_ref_exchange = ExternDecl(
        name: "kk_atomic_ref_exchange",
        parameterTypes: ["intptr_t", "intptr_t"],
        returnType: "intptr_t"
    )

    static let kk_atomic_ref_compareAndSet = ExternDecl(
        name: "kk_atomic_ref_compareAndSet",
        parameterTypes: ["intptr_t", "intptr_t", "intptr_t"],
        returnType: "intptr_t"
    )

    static let kk_atomic_ref_compareAndExchange = ExternDecl(
        name: "kk_atomic_ref_compareAndExchange",
        parameterTypes: ["intptr_t", "intptr_t", "intptr_t"],
        returnType: "intptr_t"
    )

    // MARK: - AtomicBool

    static let kk_atomic_bool_create = ExternDecl(
        name: "kk_atomic_bool_create",
        parameterTypes: ["intptr_t"],
        returnType: "intptr_t"
    )

    static let kk_atomic_bool_load = ExternDecl(
        name: "kk_atomic_bool_load",
        parameterTypes: ["intptr_t"],
        returnType: "intptr_t"
    )

    static let kk_atomic_bool_store = ExternDecl(
        name: "kk_atomic_bool_store",
        parameterTypes: ["intptr_t", "intptr_t"],
        returnType: "intptr_t"
    )

    static let kk_atomic_bool_exchange = ExternDecl(
        name: "kk_atomic_bool_exchange",
        parameterTypes: ["intptr_t", "intptr_t"],
        returnType: "intptr_t"
    )

    static let kk_atomic_bool_compareAndSet = ExternDecl(
        name: "kk_atomic_bool_compareAndSet",
        parameterTypes: ["intptr_t", "intptr_t", "intptr_t"],
        returnType: "intptr_t"
    )

    static let kk_atomic_bool_compareAndExchange = ExternDecl(
        name: "kk_atomic_bool_compareAndExchange",
        parameterTypes: ["intptr_t", "intptr_t", "intptr_t"],
        returnType: "intptr_t"
    )
}
