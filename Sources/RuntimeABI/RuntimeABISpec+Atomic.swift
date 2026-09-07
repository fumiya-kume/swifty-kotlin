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
            section: "Atomic",
            isThrowing: false
        ),
        RuntimeABIFunctionSpec(
            name: "__kk_atomic_int_load",
            parameters: [
                RuntimeABIParameter(name: "receiver", type: .intptr),
            ],
            returnType: .intptr,
            section: "Atomic",
            isThrowing: false
        ),
        RuntimeABIFunctionSpec(
            name: "__kk_atomic_int_store",
            parameters: [
                RuntimeABIParameter(name: "receiver", type: .intptr),
                RuntimeABIParameter(name: "value", type: .intptr),
            ],
            returnType: .intptr,
            section: "Atomic",
            isThrowing: false
        ),
        RuntimeABIFunctionSpec(
            name: "__kk_atomic_int_exchange",
            parameters: [
                RuntimeABIParameter(name: "receiver", type: .intptr),
                RuntimeABIParameter(name: "new", type: .intptr),
            ],
            returnType: .intptr,
            section: "Atomic",
            isThrowing: false
        ),
        RuntimeABIFunctionSpec(
            name: "kk_atomic_int_compareAndSet",
            parameters: [
                RuntimeABIParameter(name: "receiver", type: .intptr),
                RuntimeABIParameter(name: "expect", type: .intptr),
                RuntimeABIParameter(name: "update", type: .intptr),
            ],
            returnType: .intptr,
            section: "Atomic",
            isThrowing: false
        ),
        RuntimeABIFunctionSpec(
            name: "__kk_atomic_int_compareAndExchange",
            parameters: [
                RuntimeABIParameter(name: "receiver", type: .intptr),
                RuntimeABIParameter(name: "expect", type: .intptr),
                RuntimeABIParameter(name: "update", type: .intptr),
            ],
            returnType: .intptr,
            section: "Atomic",
            isThrowing: false
        ),

        RuntimeABIFunctionSpec(
            name: "__kk_atomic_int_fetchAndAdd",
            parameters: [
                RuntimeABIParameter(name: "receiver", type: .intptr),
                RuntimeABIParameter(name: "delta", type: .intptr),
            ],
            returnType: .intptr,
            section: "Atomic",
            isThrowing: false
        ),
        RuntimeABIFunctionSpec(
            name: "__kk_atomic_int_addAndFetch",
            parameters: [
                RuntimeABIParameter(name: "receiver", type: .intptr),
                RuntimeABIParameter(name: "delta", type: .intptr),
            ],
            returnType: .intptr,
            section: "Atomic",
            isThrowing: false
        ),
        RuntimeABIFunctionSpec(
            name: "__kk_atomic_int_fetchAndIncrement",
            parameters: [
                RuntimeABIParameter(name: "receiver", type: .intptr),
            ],
            returnType: .intptr,
            section: "Atomic",
            isThrowing: false
        ),
        RuntimeABIFunctionSpec(
            name: "__kk_atomic_int_fetchAndDecrement",
            parameters: [
                RuntimeABIParameter(name: "receiver", type: .intptr),
            ],
            returnType: .intptr,
            section: "Atomic",
            isThrowing: false
        ),
        RuntimeABIFunctionSpec(
            name: "__kk_atomic_int_incrementAndFetch",
            parameters: [
                RuntimeABIParameter(name: "receiver", type: .intptr),
            ],
            returnType: .intptr,
            section: "Atomic",
            isThrowing: false
        ),
        RuntimeABIFunctionSpec(
            name: "__kk_atomic_int_decrementAndFetch",
            parameters: [
                RuntimeABIParameter(name: "receiver", type: .intptr),
            ],
            returnType: .intptr,
            section: "Atomic",
            isThrowing: false
        ),
        // AtomicLong
        RuntimeABIFunctionSpec(
            name: "kk_atomic_long_create",
            parameters: [
                RuntimeABIParameter(name: "initial", type: .intptr),
            ],
            returnType: .intptr,
            section: "Atomic",
            isThrowing: false
        ),
        RuntimeABIFunctionSpec(
            name: "__kk_atomic_long_load",
            parameters: [
                RuntimeABIParameter(name: "receiver", type: .intptr),
            ],
            returnType: .intptr,
            section: "Atomic",
            isThrowing: false
        ),
        RuntimeABIFunctionSpec(
            name: "__kk_atomic_long_store",
            parameters: [
                RuntimeABIParameter(name: "receiver", type: .intptr),
                RuntimeABIParameter(name: "value", type: .intptr),
            ],
            returnType: .intptr,
            section: "Atomic",
            isThrowing: false
        ),
        RuntimeABIFunctionSpec(
            name: "__kk_atomic_long_exchange",
            parameters: [
                RuntimeABIParameter(name: "receiver", type: .intptr),
                RuntimeABIParameter(name: "new", type: .intptr),
            ],
            returnType: .intptr,
            section: "Atomic",
            isThrowing: false
        ),
        RuntimeABIFunctionSpec(
            name: "kk_atomic_long_compareAndSet",
            parameters: [
                RuntimeABIParameter(name: "receiver", type: .intptr),
                RuntimeABIParameter(name: "expect", type: .intptr),
                RuntimeABIParameter(name: "update", type: .intptr),
            ],
            returnType: .intptr,
            section: "Atomic",
            isThrowing: false
        ),
        RuntimeABIFunctionSpec(
            name: "__kk_atomic_long_compareAndExchange",
            parameters: [
                RuntimeABIParameter(name: "receiver", type: .intptr),
                RuntimeABIParameter(name: "expect", type: .intptr),
                RuntimeABIParameter(name: "update", type: .intptr),
            ],
            returnType: .intptr,
            section: "Atomic",
            isThrowing: false
        ),

        RuntimeABIFunctionSpec(
            name: "__kk_atomic_long_fetchAndAdd",
            parameters: [
                RuntimeABIParameter(name: "receiver", type: .intptr),
                RuntimeABIParameter(name: "delta", type: .intptr),
            ],
            returnType: .intptr,
            section: "Atomic",
            isThrowing: false
        ),
        RuntimeABIFunctionSpec(
            name: "__kk_atomic_long_addAndFetch",
            parameters: [
                RuntimeABIParameter(name: "receiver", type: .intptr),
                RuntimeABIParameter(name: "delta", type: .intptr),
            ],
            returnType: .intptr,
            section: "Atomic",
            isThrowing: false
        ),
        RuntimeABIFunctionSpec(
            name: "__kk_atomic_long_fetchAndIncrement",
            parameters: [
                RuntimeABIParameter(name: "receiver", type: .intptr),
            ],
            returnType: .intptr,
            section: "Atomic",
            isThrowing: false
        ),
        RuntimeABIFunctionSpec(
            name: "__kk_atomic_long_fetchAndDecrement",
            parameters: [
                RuntimeABIParameter(name: "receiver", type: .intptr),
            ],
            returnType: .intptr,
            section: "Atomic",
            isThrowing: false
        ),
        RuntimeABIFunctionSpec(
            name: "__kk_atomic_long_incrementAndFetch",
            parameters: [
                RuntimeABIParameter(name: "receiver", type: .intptr),
            ],
            returnType: .intptr,
            section: "Atomic",
            isThrowing: false
        ),
        RuntimeABIFunctionSpec(
            name: "__kk_atomic_long_decrementAndFetch",
            parameters: [
                RuntimeABIParameter(name: "receiver", type: .intptr),
            ],
            returnType: .intptr,
            section: "Atomic",
            isThrowing: false
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
        // KSP-672: raw synchronized-core bridges (bounds checks live in Kotlin).
        RuntimeABIFunctionSpec(
            name: "__kk_atomic_int_array_load",
            parameters: [
                RuntimeABIParameter(name: "receiver", type: .intptr),
                RuntimeABIParameter(name: "index", type: .intptr),
            ],
            returnType: .intptr,
            section: "Atomic",
            isThrowing: false
        ),
        RuntimeABIFunctionSpec(
            name: "__kk_atomic_int_array_store",
            parameters: [
                RuntimeABIParameter(name: "receiver", type: .intptr),
                RuntimeABIParameter(name: "index", type: .intptr),
                RuntimeABIParameter(name: "value", type: .intptr),
            ],
            returnType: .intptr,
            section: "Atomic",
            isThrowing: false
        ),
        RuntimeABIFunctionSpec(
            name: "__kk_atomic_int_array_exchange",
            parameters: [
                RuntimeABIParameter(name: "receiver", type: .intptr),
                RuntimeABIParameter(name: "index", type: .intptr),
                RuntimeABIParameter(name: "newValue", type: .intptr),
            ],
            returnType: .intptr,
            section: "Atomic",
            isThrowing: false
        ),
        RuntimeABIFunctionSpec(
            name: "__kk_atomic_int_array_compareAndExchange",
            parameters: [
                RuntimeABIParameter(name: "receiver", type: .intptr),
                RuntimeABIParameter(name: "index", type: .intptr),
                RuntimeABIParameter(name: "expect", type: .intptr),
                RuntimeABIParameter(name: "update", type: .intptr),
            ],
            returnType: .intptr,
            section: "Atomic",
            isThrowing: false
        ),


        RuntimeABIFunctionSpec(
            name: "__kk_atomic_int_array_fetchAndAdd",
            parameters: [
                RuntimeABIParameter(name: "receiver", type: .intptr),
                RuntimeABIParameter(name: "index", type: .intptr),
                RuntimeABIParameter(name: "delta", type: .intptr),
            ],
            returnType: .intptr,
            section: "Atomic",
            isThrowing: false
        ),
        RuntimeABIFunctionSpec(
            name: "__kk_atomic_int_array_addAndFetch",
            parameters: [
                RuntimeABIParameter(name: "receiver", type: .intptr),
                RuntimeABIParameter(name: "index", type: .intptr),
                RuntimeABIParameter(name: "delta", type: .intptr),
            ],
            returnType: .intptr,
            section: "Atomic",
            isThrowing: false
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
        // KSP-672: raw synchronized-core bridges (bounds checks live in Kotlin).
        RuntimeABIFunctionSpec(
            name: "__kk_atomic_long_array_load",
            parameters: [
                RuntimeABIParameter(name: "receiver", type: .intptr),
                RuntimeABIParameter(name: "index", type: .intptr),
            ],
            returnType: .intptr,
            section: "Atomic",
            isThrowing: false
        ),
        RuntimeABIFunctionSpec(
            name: "__kk_atomic_long_array_store",
            parameters: [
                RuntimeABIParameter(name: "receiver", type: .intptr),
                RuntimeABIParameter(name: "index", type: .intptr),
                RuntimeABIParameter(name: "value", type: .intptr),
            ],
            returnType: .intptr,
            section: "Atomic",
            isThrowing: false
        ),
        RuntimeABIFunctionSpec(
            name: "__kk_atomic_long_array_exchange",
            parameters: [
                RuntimeABIParameter(name: "receiver", type: .intptr),
                RuntimeABIParameter(name: "index", type: .intptr),
                RuntimeABIParameter(name: "newValue", type: .intptr),
            ],
            returnType: .intptr,
            section: "Atomic",
            isThrowing: false
        ),
        RuntimeABIFunctionSpec(
            name: "__kk_atomic_long_array_compareAndExchange",
            parameters: [
                RuntimeABIParameter(name: "receiver", type: .intptr),
                RuntimeABIParameter(name: "index", type: .intptr),
                RuntimeABIParameter(name: "expect", type: .intptr),
                RuntimeABIParameter(name: "update", type: .intptr),
            ],
            returnType: .intptr,
            section: "Atomic",
            isThrowing: false
        ),

        RuntimeABIFunctionSpec(
            name: "__kk_atomic_long_array_fetchAndAdd",
            parameters: [
                RuntimeABIParameter(name: "receiver", type: .intptr),
                RuntimeABIParameter(name: "index", type: .intptr),
                RuntimeABIParameter(name: "delta", type: .intptr),
            ],
            returnType: .intptr,
            section: "Atomic",
            isThrowing: false
        ),
        RuntimeABIFunctionSpec(
            name: "__kk_atomic_long_array_addAndFetch",
            parameters: [
                RuntimeABIParameter(name: "receiver", type: .intptr),
                RuntimeABIParameter(name: "index", type: .intptr),
                RuntimeABIParameter(name: "delta", type: .intptr),
            ],
            returnType: .intptr,
            section: "Atomic",
            isThrowing: false
        ),
        // AtomicArray<T>
        RuntimeABIFunctionSpec(
            name: "kk_atomic_ref_array_exchangeAt",
            parameters: [
                RuntimeABIParameter(name: "receiver", type: .intptr),
                RuntimeABIParameter(name: "index", type: .intptr),
                RuntimeABIParameter(name: "newValue", type: .intptr),
            ],
            returnType: .intptr,
            section: "Atomic",
            isThrowing: false
        ),
        // AtomicArray

        // AtomicBoolean
        RuntimeABIFunctionSpec(
            name: "kk_atomic_bool_create",
            parameters: [
                RuntimeABIParameter(name: "initial", type: .intptr),
            ],
            returnType: .intptr,
            section: "Atomic",
            isThrowing: false
        ),
        RuntimeABIFunctionSpec(
            name: "__kk_atomic_bool_load",
            parameters: [
                RuntimeABIParameter(name: "receiver", type: .intptr),
            ],
            returnType: .intptr,
            section: "Atomic",
            isThrowing: false
        ),
        RuntimeABIFunctionSpec(
            name: "__kk_atomic_bool_store",
            parameters: [
                RuntimeABIParameter(name: "receiver", type: .intptr),
                RuntimeABIParameter(name: "value", type: .intptr),
            ],
            returnType: .intptr,
            section: "Atomic",
            isThrowing: false
        ),
        RuntimeABIFunctionSpec(
            name: "__kk_atomic_bool_exchange",
            parameters: [
                RuntimeABIParameter(name: "receiver", type: .intptr),
                RuntimeABIParameter(name: "new", type: .intptr),
            ],
            returnType: .intptr,
            section: "Atomic",
            isThrowing: false
        ),
        RuntimeABIFunctionSpec(
            name: "__kk_atomic_bool_compareAndExchange",
            parameters: [
                RuntimeABIParameter(name: "receiver", type: .intptr),
                RuntimeABIParameter(name: "expect", type: .intptr),
                RuntimeABIParameter(name: "update", type: .intptr),
            ],
            returnType: .intptr,
            section: "Atomic",
            isThrowing: false
        ),

        RuntimeABIFunctionSpec(
            name: "kk_atomic_ref_array_of",
            parameters: [
                RuntimeABIParameter(name: "elements", type: .intptr),
            ],
            returnType: .intptr,
            section: "Atomic",
            isThrowing: false
        ),
        // AtomicReference
        RuntimeABIFunctionSpec(
            name: "kk_atomic_ref_create",
            parameters: [
                RuntimeABIParameter(name: "initial", type: .intptr),
            ],
            returnType: .intptr,
            section: "Atomic",
            isThrowing: false
        ),
        RuntimeABIFunctionSpec(
            name: "__kk_atomic_ref_load",
            parameters: [
                RuntimeABIParameter(name: "receiver", type: .intptr),
            ],
            returnType: .intptr,
            section: "Atomic",
            isThrowing: false
        ),
        RuntimeABIFunctionSpec(
            name: "__kk_atomic_ref_store",
            parameters: [
                RuntimeABIParameter(name: "receiver", type: .intptr),
                RuntimeABIParameter(name: "value", type: .intptr),
            ],
            returnType: .intptr,
            section: "Atomic",
            isThrowing: false
        ),
        RuntimeABIFunctionSpec(
            name: "__kk_atomic_ref_exchange",
            parameters: [
                RuntimeABIParameter(name: "receiver", type: .intptr),
                RuntimeABIParameter(name: "new", type: .intptr),
            ],
            returnType: .intptr,
            section: "Atomic",
            isThrowing: false
        ),
        RuntimeABIFunctionSpec(
            name: "__kk_atomic_ref_compareAndExchange",
            parameters: [
                RuntimeABIParameter(name: "receiver", type: .intptr),
                RuntimeABIParameter(name: "expect", type: .intptr),
                RuntimeABIParameter(name: "update", type: .intptr),
            ],
            returnType: .intptr,
            section: "Atomic",
            isThrowing: false
        ),

        // AtomicArray<T>
        RuntimeABIFunctionSpec(
            name: "kk_atomic_ref_array_compareAndSetAt",
            parameters: [
                RuntimeABIParameter(name: "receiver", type: .intptr),
                RuntimeABIParameter(name: "index", type: .intptr),
                RuntimeABIParameter(name: "expect", type: .intptr),
                RuntimeABIParameter(name: "update", type: .intptr),
            ],
            returnType: .intptr,
            section: "Atomic"
        ),
    ]
}
