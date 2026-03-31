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
        RuntimeABIFunctionSpec(
            name: "kk_atomic_int_getAndUpdate",
            parameters: [
                RuntimeABIParameter(name: "receiver", type: .intptr),
                RuntimeABIParameter(name: "fn", type: .intptr),
            ],
            returnType: .intptr,
            section: "Atomic"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_atomic_int_updateAndGet",
            parameters: [
                RuntimeABIParameter(name: "receiver", type: .intptr),
                RuntimeABIParameter(name: "fn", type: .intptr),
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
        RuntimeABIFunctionSpec(
            name: "kk_atomic_long_getAndUpdate",
            parameters: [
                RuntimeABIParameter(name: "receiver", type: .intptr),
                RuntimeABIParameter(name: "fn", type: .intptr),
            ],
            returnType: .intptr,
            section: "Atomic"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_atomic_long_updateAndGet",
            parameters: [
                RuntimeABIParameter(name: "receiver", type: .intptr),
                RuntimeABIParameter(name: "fn", type: .intptr),
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
        RuntimeABIFunctionSpec(
            name: "kk_atomic_ref_getAndUpdate",
            parameters: [
                RuntimeABIParameter(name: "receiver", type: .intptr),
                RuntimeABIParameter(name: "fn", type: .intptr),
            ],
            returnType: .intptr,
            section: "Atomic"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_atomic_ref_updateAndGet",
            parameters: [
                RuntimeABIParameter(name: "receiver", type: .intptr),
                RuntimeABIParameter(name: "fn", type: .intptr),
            ],
            returnType: .intptr,
            section: "Atomic"
        ),
        // AtomicBoolean
        RuntimeABIFunctionSpec(
            name: "kk_atomic_boolean_create",
            parameters: [
                RuntimeABIParameter(name: "initial", type: .intptr),
            ],
            returnType: .intptr,
            section: "Atomic"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_atomic_boolean_load",
            parameters: [
                RuntimeABIParameter(name: "receiver", type: .intptr),
            ],
            returnType: .intptr,
            section: "Atomic"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_atomic_boolean_store",
            parameters: [
                RuntimeABIParameter(name: "receiver", type: .intptr),
                RuntimeABIParameter(name: "value", type: .intptr),
            ],
            returnType: .intptr,
            section: "Atomic"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_atomic_boolean_exchange",
            parameters: [
                RuntimeABIParameter(name: "receiver", type: .intptr),
                RuntimeABIParameter(name: "new", type: .intptr),
            ],
            returnType: .intptr,
            section: "Atomic"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_atomic_boolean_compareAndSet",
            parameters: [
                RuntimeABIParameter(name: "receiver", type: .intptr),
                RuntimeABIParameter(name: "expect", type: .intptr),
                RuntimeABIParameter(name: "update", type: .intptr),
            ],
            returnType: .intptr,
            section: "Atomic"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_atomic_boolean_compareAndExchange",
            parameters: [
                RuntimeABIParameter(name: "receiver", type: .intptr),
                RuntimeABIParameter(name: "expect", type: .intptr),
                RuntimeABIParameter(name: "update", type: .intptr),
            ],
            returnType: .intptr,
            section: "Atomic"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_atomic_boolean_getAndUpdate",
            parameters: [
                RuntimeABIParameter(name: "receiver", type: .intptr),
                RuntimeABIParameter(name: "fn", type: .intptr),
            ],
            returnType: .intptr,
            section: "Atomic"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_atomic_boolean_updateAndGet",
            parameters: [
                RuntimeABIParameter(name: "receiver", type: .intptr),
                RuntimeABIParameter(name: "fn", type: .intptr),
            ],
            returnType: .intptr,
            section: "Atomic"
        ),
    ]
}
