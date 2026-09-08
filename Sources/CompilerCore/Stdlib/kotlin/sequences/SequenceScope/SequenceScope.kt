package kotlin.sequences

import kotlin.coroutines.RestrictsSuspension

// KSP-1361: SequenceScope is source-backed while the sequence builder
// suspension points remain compiler/runtime-owned through the existing
// __kk_sequence_builder_* lowering bridges.
@RestrictsSuspension
@SinceKotlin("1.3")
public abstract class SequenceScope<in T> internal constructor() {
    public abstract suspend fun yield(value: T)

    public abstract suspend fun yieldAll(iterator: Iterator<T>)

    public suspend fun yieldAll(elements: Iterable<T>) {
        if (elements is Collection && elements.isEmpty()) return
        return yieldAll(elements.iterator())
    }

    public suspend fun yieldAll(sequence: Sequence<T>): Unit = yieldAll(sequence.iterator())
}
