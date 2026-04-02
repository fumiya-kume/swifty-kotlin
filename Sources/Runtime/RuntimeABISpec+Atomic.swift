// Atomic functions (kotlin.concurrent.AtomicInt / AtomicLong / AtomicReference / atomics.AtomicArray).

public extension RuntimeABISpec {
    static let atomicFunctions: [RuntimeABIFunctionSpec] = [
        // AtomicInt
        RuntimeABIFunctionSpec(
            name: "kk_atomic_int_create",
            parameters: [
                RuntimeABIParameter(name: "initial", type: .intptr),
            ],
            returnType: .intptr,
            section: "Atomic"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_atomic_int_load",
            parameters: [
                RuntimeABIParameter(name: "receiver", type: .intptr),
            ],
            returnType: .intptr,
            section: "Atomic"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_atomic_int_store",
            parameters: [
                RuntimeABIParameter(name: "receiver", type: .intptr),
                RuntimeABIParameter(name: "value", type: .intptr),
            ],
            returnType: .intptr,
            section: "Atomic"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_atomic_int_exchange",
            parameters: [
                RuntimeABIParameter(name: "receiver", type: .intptr),
                RuntimeABIParameter(name: "new", type: .intptr),
            ],
            returnType: .intptr,
            section: "Atomic"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_atomic_int_compareAndSet",
            parameters: [
                RuntimeABIParameter(name: "receiver", type: .intptr),
                RuntimeABIParameter(name: "expect", type: .intptr),
                RuntimeABIParameter(name: "update", type: .intptr),
            ],
            returnType: .intptr,
            section: "Atomic"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_atomic_int_compareAndExchange",
            parameters: [
                RuntimeABIParameter(name: "receiver", type: .intptr),
                RuntimeABIParameter(name: "expect", type: .intptr),
                RuntimeABIParameter(name: "update", type: .intptr),
            ],
            returnType: .intptr,
            section: "Atomic"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_atomic_int_fetchAndAdd",
            parameters: [
                RuntimeABIParameter(name: "receiver", type: .intptr),
                RuntimeABIParameter(name: "delta", type: .intptr),
            ],
            returnType: .intptr,
            section: "Atomic"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_atomic_int_addAndFetch",
            parameters: [
                RuntimeABIParameter(name: "receiver", type: .intptr),
                RuntimeABIParameter(name: "delta", type: .intptr),
            ],
            returnType: .intptr,
            section: "Atomic"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_atomic_int_fetchAndIncrement",
            parameters: [
                RuntimeABIParameter(name: "receiver", type: .intptr),
            ],
            returnType: .intptr,
            section: "Atomic"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_atomic_int_incrementAndFetch",
            parameters: [
                RuntimeABIParameter(name: "receiver", type: .intptr),
            ],
            returnType: .intptr,
            section: "Atomic"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_atomic_int_decrementAndFetch",
            parameters: [
                RuntimeABIParameter(name: "receiver", type: .intptr),
            ],
            returnType: .intptr,
            section: "Atomic"
        ),
        // AtomicInt getAndUpdate / updateAndGet
        RuntimeABIFunctionSpec(
            name: "kk_atomic_int_getAndUpdate",
            parameters: [
                RuntimeABIParameter(name: "receiver", type: .intptr),
                RuntimeABIParameter(name: "updateFn", type: .intptr),
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "Atomic"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_atomic_int_updateAndGet",
            parameters: [
                RuntimeABIParameter(name: "receiver", type: .intptr),
                RuntimeABIParameter(name: "updateFn", type: .intptr),
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "Atomic"
        ),
        // AtomicLong
        RuntimeABIFunctionSpec(
            name: "kk_atomic_long_create",
            parameters: [
                RuntimeABIParameter(name: "initial", type: .intptr),
            ],
            returnType: .intptr,
            section: "Atomic"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_atomic_long_load",
            parameters: [
                RuntimeABIParameter(name: "receiver", type: .intptr),
            ],
            returnType: .intptr,
            section: "Atomic"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_atomic_long_store",
            parameters: [
                RuntimeABIParameter(name: "receiver", type: .intptr),
                RuntimeABIParameter(name: "value", type: .intptr),
            ],
            returnType: .intptr,
            section: "Atomic"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_atomic_long_exchange",
            parameters: [
                RuntimeABIParameter(name: "receiver", type: .intptr),
                RuntimeABIParameter(name: "new", type: .intptr),
            ],
            returnType: .intptr,
            section: "Atomic"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_atomic_long_compareAndSet",
            parameters: [
                RuntimeABIParameter(name: "receiver", type: .intptr),
                RuntimeABIParameter(name: "expect", type: .intptr),
                RuntimeABIParameter(name: "update", type: .intptr),
            ],
            returnType: .intptr,
            section: "Atomic"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_atomic_long_compareAndExchange",
            parameters: [
                RuntimeABIParameter(name: "receiver", type: .intptr),
                RuntimeABIParameter(name: "expect", type: .intptr),
                RuntimeABIParameter(name: "update", type: .intptr),
            ],
            returnType: .intptr,
            section: "Atomic"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_atomic_long_fetchAndAdd",
            parameters: [
                RuntimeABIParameter(name: "receiver", type: .intptr),
                RuntimeABIParameter(name: "delta", type: .intptr),
            ],
            returnType: .intptr,
            section: "Atomic"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_atomic_long_addAndFetch",
            parameters: [
                RuntimeABIParameter(name: "receiver", type: .intptr),
                RuntimeABIParameter(name: "delta", type: .intptr),
            ],
            returnType: .intptr,
            section: "Atomic"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_atomic_long_fetchAndIncrement",
            parameters: [
                RuntimeABIParameter(name: "receiver", type: .intptr),
            ],
            returnType: .intptr,
            section: "Atomic"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_atomic_long_incrementAndFetch",
            parameters: [
                RuntimeABIParameter(name: "receiver", type: .intptr),
            ],
            returnType: .intptr,
            section: "Atomic"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_atomic_long_decrementAndFetch",
            parameters: [
                RuntimeABIParameter(name: "receiver", type: .intptr),
            ],
            returnType: .intptr,
            section: "Atomic"
        ),
        // AtomicInt getAndUpdate / updateAndGet
        RuntimeABIFunctionSpec(
            name: "kk_atomic_int_getAndUpdate",
            parameters: [
                RuntimeABIParameter(name: "receiver", type: .intptr),
                RuntimeABIParameter(name: "updateFn", type: .intptr),
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "Atomic"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_atomic_int_updateAndGet",
            parameters: [
                RuntimeABIParameter(name: "receiver", type: .intptr),
                RuntimeABIParameter(name: "updateFn", type: .intptr),
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "Atomic"
        ),
        // AtomicLong getAndUpdate / updateAndGet
        RuntimeABIFunctionSpec(
            name: "kk_atomic_long_getAndUpdate",
            parameters: [
                RuntimeABIParameter(name: "receiver", type: .intptr),
                RuntimeABIParameter(name: "updateFn", type: .intptr),
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "Atomic"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_atomic_long_updateAndGet",
            parameters: [
                RuntimeABIParameter(name: "receiver", type: .intptr),
                RuntimeABIParameter(name: "updateFn", type: .intptr),
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "Atomic"
        ),
        // AtomicBoolean
        RuntimeABIFunctionSpec(
            name: "kk_atomic_bool_create",
            parameters: [
                RuntimeABIParameter(name: "initial", type: .intptr),
            ],
            returnType: .intptr,
            section: "Atomic"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_atomic_bool_load",
            parameters: [
                RuntimeABIParameter(name: "receiver", type: .intptr),
            ],
            returnType: .intptr,
            section: "Atomic"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_atomic_bool_store",
            parameters: [
                RuntimeABIParameter(name: "receiver", type: .intptr),
                RuntimeABIParameter(name: "value", type: .intptr),
            ],
            returnType: .intptr,
            section: "Atomic"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_atomic_bool_exchange",
            parameters: [
                RuntimeABIParameter(name: "receiver", type: .intptr),
                RuntimeABIParameter(name: "new", type: .intptr),
            ],
            returnType: .intptr,
            section: "Atomic"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_atomic_bool_compareAndSet",
            parameters: [
                RuntimeABIParameter(name: "receiver", type: .intptr),
                RuntimeABIParameter(name: "expect", type: .intptr),
                RuntimeABIParameter(name: "update", type: .intptr),
            ],
            returnType: .intptr,
            section: "Atomic"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_atomic_bool_compareAndExchange",
            parameters: [
                RuntimeABIParameter(name: "receiver", type: .intptr),
                RuntimeABIParameter(name: "expect", type: .intptr),
                RuntimeABIParameter(name: "update", type: .intptr),
            ],
            returnType: .intptr,
            section: "Atomic"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_atomic_bool_getAndUpdate",
            parameters: [
                RuntimeABIParameter(name: "receiver", type: .intptr),
                RuntimeABIParameter(name: "updateFn", type: .intptr),
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "Atomic"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_atomic_bool_updateAndGet",
            parameters: [
                RuntimeABIParameter(name: "receiver", type: .intptr),
                RuntimeABIParameter(name: "updateFn", type: .intptr),
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "Atomic"
        ),
        // AtomicReference getAndUpdate / updateAndGet
        RuntimeABIFunctionSpec(
            name: "kk_atomic_ref_getAndUpdate",
            parameters: [
                RuntimeABIParameter(name: "receiver", type: .intptr),
                RuntimeABIParameter(name: "updateFn", type: .intptr),
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "Atomic"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_atomic_ref_updateAndGet",
            parameters: [
                RuntimeABIParameter(name: "receiver", type: .intptr),
                RuntimeABIParameter(name: "updateFn", type: .intptr),
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "Atomic"
        ),
        // AtomicReference
        RuntimeABIFunctionSpec(
            name: "kk_atomic_ref_create",
            parameters: [
                RuntimeABIParameter(name: "initial", type: .intptr),
            ],
            returnType: .intptr,
            section: "Atomic"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_atomic_ref_load",
            parameters: [
                RuntimeABIParameter(name: "receiver", type: .intptr),
            ],
            returnType: .intptr,
            section: "Atomic"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_atomic_ref_store",
            parameters: [
                RuntimeABIParameter(name: "receiver", type: .intptr),
                RuntimeABIParameter(name: "value", type: .intptr),
            ],
            returnType: .intptr,
            section: "Atomic"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_atomic_ref_exchange",
            parameters: [
                RuntimeABIParameter(name: "receiver", type: .intptr),
                RuntimeABIParameter(name: "new", type: .intptr),
            ],
            returnType: .intptr,
            section: "Atomic"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_atomic_ref_compareAndSet",
            parameters: [
                RuntimeABIParameter(name: "receiver", type: .intptr),
                RuntimeABIParameter(name: "expect", type: .intptr),
                RuntimeABIParameter(name: "update", type: .intptr),
            ],
            returnType: .intptr,
            section: "Atomic"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_atomic_ref_compareAndExchange",
            parameters: [
                RuntimeABIParameter(name: "receiver", type: .intptr),
                RuntimeABIParameter(name: "expect", type: .intptr),
                RuntimeABIParameter(name: "update", type: .intptr),
            ],
            returnType: .intptr,
            section: "Atomic"
        ),
        // AtomicArray
        RuntimeABIFunctionSpec(
            name: "kk_atomic_array_create",
            parameters: [
                RuntimeABIParameter(name: "array", type: .intptr),
            ],
            returnType: .intptr,
            section: "Atomic"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_atomic_array_new",
            parameters: [
                RuntimeABIParameter(name: "size", type: .intptr),
                RuntimeABIParameter(name: "initFn", type: .intptr),
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "Atomic"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_atomic_array_ofNulls",
            parameters: [
                RuntimeABIParameter(name: "size", type: .intptr),
            ],
            returnType: .intptr,
            section: "Atomic"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_atomic_array_size",
            parameters: [
                RuntimeABIParameter(name: "receiver", type: .intptr),
            ],
            returnType: .intptr,
            section: "Atomic"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_atomic_array_loadAt",
            parameters: [
                RuntimeABIParameter(name: "receiver", type: .intptr),
                RuntimeABIParameter(name: "index", type: .intptr),
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "Atomic"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_atomic_array_storeAt",
            parameters: [
                RuntimeABIParameter(name: "receiver", type: .intptr),
                RuntimeABIParameter(name: "index", type: .intptr),
                RuntimeABIParameter(name: "value", type: .intptr),
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "Atomic"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_atomic_array_exchangeAt",
            parameters: [
                RuntimeABIParameter(name: "receiver", type: .intptr),
                RuntimeABIParameter(name: "index", type: .intptr),
                RuntimeABIParameter(name: "new", type: .intptr),
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "Atomic"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_atomic_array_compareAndSetAt",
            parameters: [
                RuntimeABIParameter(name: "receiver", type: .intptr),
                RuntimeABIParameter(name: "index", type: .intptr),
                RuntimeABIParameter(name: "expect", type: .intptr),
                RuntimeABIParameter(name: "update", type: .intptr),
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "Atomic"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_atomic_array_compareAndExchangeAt",
            parameters: [
                RuntimeABIParameter(name: "receiver", type: .intptr),
                RuntimeABIParameter(name: "index", type: .intptr),
                RuntimeABIParameter(name: "expect", type: .intptr),
                RuntimeABIParameter(name: "update", type: .intptr),
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "Atomic"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_atomic_array_fetchAndUpdateAt",
            parameters: [
                RuntimeABIParameter(name: "receiver", type: .intptr),
                RuntimeABIParameter(name: "index", type: .intptr),
                RuntimeABIParameter(name: "updateFn", type: .intptr),
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "Atomic"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_atomic_array_updateAndFetchAt",
            parameters: [
                RuntimeABIParameter(name: "receiver", type: .intptr),
                RuntimeABIParameter(name: "index", type: .intptr),
                RuntimeABIParameter(name: "updateFn", type: .intptr),
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "Atomic"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_atomic_array_updateAt",
            parameters: [
                RuntimeABIParameter(name: "receiver", type: .intptr),
                RuntimeABIParameter(name: "index", type: .intptr),
                RuntimeABIParameter(name: "updateFn", type: .intptr),
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "Atomic"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_atomic_array_toString",
            parameters: [
                RuntimeABIParameter(name: "receiver", type: .intptr),
            ],
            returnType: .opaquePointer,
            section: "Atomic"
        ),
    ]
}
