// Atomic functions (kotlin.concurrent.AtomicInt / AtomicLong / AtomicReference).

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
        // AtomicIntArray
        RuntimeABIFunctionSpec(
            name: "kk_atomic_int_array_create",
            parameters: [
                RuntimeABIParameter(name: "size", type: .intptr),
            ],
            returnType: .intptr,
            section: "Atomic"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_atomic_int_array_size",
            parameters: [
                RuntimeABIParameter(name: "receiver", type: .intptr),
            ],
            returnType: .intptr,
            section: "Atomic"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_atomic_int_array_loadAt",
            parameters: [
                RuntimeABIParameter(name: "receiver", type: .intptr),
                RuntimeABIParameter(name: "index", type: .intptr),
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "Atomic"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_atomic_int_array_storeAt",
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
            name: "kk_atomic_int_array_exchangeAt",
            parameters: [
                RuntimeABIParameter(name: "receiver", type: .intptr),
                RuntimeABIParameter(name: "index", type: .intptr),
                RuntimeABIParameter(name: "newValue", type: .intptr),
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "Atomic"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_atomic_int_array_compareAndSetAt",
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
            name: "kk_atomic_int_array_compareAndExchangeAt",
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
            name: "kk_atomic_int_array_fetchAndAddAt",
            parameters: [
                RuntimeABIParameter(name: "receiver", type: .intptr),
                RuntimeABIParameter(name: "index", type: .intptr),
                RuntimeABIParameter(name: "delta", type: .intptr),
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "Atomic"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_atomic_int_array_addAndFetchAt",
            parameters: [
                RuntimeABIParameter(name: "receiver", type: .intptr),
                RuntimeABIParameter(name: "index", type: .intptr),
                RuntimeABIParameter(name: "delta", type: .intptr),
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "Atomic"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_atomic_int_array_incrementAndFetchAt",
            parameters: [
                RuntimeABIParameter(name: "receiver", type: .intptr),
                RuntimeABIParameter(name: "index", type: .intptr),
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "Atomic"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_atomic_int_array_decrementAndFetchAt",
            parameters: [
                RuntimeABIParameter(name: "receiver", type: .intptr),
                RuntimeABIParameter(name: "index", type: .intptr),
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "Atomic"
        ),
        // AtomicLongArray
        RuntimeABIFunctionSpec(
            name: "kk_atomic_long_array_create",
            parameters: [
                RuntimeABIParameter(name: "size", type: .intptr),
            ],
            returnType: .intptr,
            section: "Atomic"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_atomic_long_array_size",
            parameters: [
                RuntimeABIParameter(name: "receiver", type: .intptr),
            ],
            returnType: .intptr,
            section: "Atomic"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_atomic_long_array_loadAt",
            parameters: [
                RuntimeABIParameter(name: "receiver", type: .intptr),
                RuntimeABIParameter(name: "index", type: .intptr),
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "Atomic"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_atomic_long_array_storeAt",
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
            name: "kk_atomic_long_array_exchangeAt",
            parameters: [
                RuntimeABIParameter(name: "receiver", type: .intptr),
                RuntimeABIParameter(name: "index", type: .intptr),
                RuntimeABIParameter(name: "newValue", type: .intptr),
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "Atomic"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_atomic_long_array_compareAndSetAt",
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
            name: "kk_atomic_long_array_compareAndExchangeAt",
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
            name: "kk_atomic_long_array_fetchAndAddAt",
            parameters: [
                RuntimeABIParameter(name: "receiver", type: .intptr),
                RuntimeABIParameter(name: "index", type: .intptr),
                RuntimeABIParameter(name: "delta", type: .intptr),
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "Atomic"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_atomic_long_array_addAndFetchAt",
            parameters: [
                RuntimeABIParameter(name: "receiver", type: .intptr),
                RuntimeABIParameter(name: "index", type: .intptr),
                RuntimeABIParameter(name: "delta", type: .intptr),
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "Atomic"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_atomic_long_array_incrementAndFetchAt",
            parameters: [
                RuntimeABIParameter(name: "receiver", type: .intptr),
                RuntimeABIParameter(name: "index", type: .intptr),
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "Atomic"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_atomic_long_array_decrementAndFetchAt",
            parameters: [
                RuntimeABIParameter(name: "receiver", type: .intptr),
                RuntimeABIParameter(name: "index", type: .intptr),
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
    ]
}
