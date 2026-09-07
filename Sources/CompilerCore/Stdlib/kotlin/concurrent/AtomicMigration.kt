package kotlin.concurrent

import java.util.concurrent.atomic.AtomicInteger
import kotlin.internal.KsSymbolName

// MIGRATION-ATOMIC-001 / KSP-670 / KSP-688
// AtomicInt / AtomicLong / AtomicReference / AtomicBoolean API migrated to
// Kotlin source.
// get/set/getAndSet delegate to load/store/exchange bridge members;
// incrementAndGet/decrementAndGet/addAndGet delegate to the
// incrementAndFetch/decrementAndFetch/addAndFetch bridge members.
// KSP-671: the fetchAnd* reverse variants and compareAndSet delegate to the
// same retained bridge members (addAndFetch/incrementAndFetch/
// decrementAndFetch/compareAndExchange). The CPU-instruction cores stay as
// internal bridges; their public Kotlin API wrappers are defined below.
// KSP-688: AtomicBoolean and AtomicReference compareAndSet use the same
// compareAndExchange delegation. AtomicReference compares references by
// identity, so its wrapper uses referential equality (===).
// getAndUpdate/updateAndGet/fetchAndUpdate/updateAndFetch are CAS retry loops
// built on the load/compareAndSet members (KSP-CAP-004 / KSP-673).
// java.util.concurrent.atomic.AtomicInteger shares the scalar __kk_atomic_int_*
// core bridge, so its update operators are migrated here as well.
// Migration source: Sources/Runtime/RuntimeAtomic.swift
//   __kk_atomic_int_*/__kk_atomic_long_*/__kk_atomic_bool_*/__kk_atomic_ref_*

// Scalar atomic operations are runtime-backed cores. Keep their public Kotlin
// surface in this bundled source while exposing only internal bridge symbols.
@KsSymbolName("__kk_atomic_int_compareAndExchange")
private external fun AtomicInt.__kkCompareAndExchange(expectedValue: Int, newValue: Int): Int

@KsSymbolName("__kk_atomic_long_compareAndExchange")
private external fun AtomicLong.__kkCompareAndExchange(expectedValue: Long, newValue: Long): Long

@KsSymbolName("__kk_atomic_bool_compareAndExchange")
private external fun AtomicBoolean.__kkCompareAndExchange(expectedValue: Boolean, newValue: Boolean): Boolean

@KsSymbolName("__kk_atomic_ref_compareAndExchange")
private external fun <T> AtomicReference<T>.__kkCompareAndExchange(expectedValue: T, newValue: T): T

// ── AtomicInt ──────────────────────────────────────────────────────────────

public fun AtomicInt.compareAndExchange(expectedValue: Int, newValue: Int): Int =
    __kkCompareAndExchange(expectedValue, newValue)

public fun AtomicInt.get(): Int = load()

public fun AtomicInt.set(value: Int): Unit = store(value)

public fun AtomicInt.getAndSet(newValue: Int): Int = exchange(newValue)

public fun AtomicInt.incrementAndGet(): Int = incrementAndFetch()

public fun AtomicInt.decrementAndGet(): Int = decrementAndFetch()

public fun AtomicInt.addAndGet(delta: Int): Int = addAndFetch(delta)

public fun AtomicInt.fetchAndAdd(delta: Int): Int = addAndFetch(delta) - delta

public fun AtomicInt.fetchAndIncrement(): Int = incrementAndFetch() - 1

public fun AtomicInt.fetchAndDecrement(): Int = decrementAndFetch() + 1

public fun AtomicInt.compareAndSet(expectedValue: Int, newValue: Int): Boolean =
    compareAndExchange(expectedValue, newValue) == expectedValue

public fun AtomicInt.getAndUpdate(transform: (Int) -> Int): Int {
    while (true) {
        val old = load()
        val newValue = transform(old)
        if (compareAndSet(old, newValue)) return old
    }
}

public fun AtomicInt.updateAndGet(transform: (Int) -> Int): Int {
    while (true) {
        val old = load()
        val newValue = transform(old)
        if (compareAndSet(old, newValue)) return newValue
    }
}

public fun AtomicInt.fetchAndUpdate(transform: (Int) -> Int): Int {
    while (true) {
        val old = load()
        val newValue = transform(old)
        if (compareAndSet(old, newValue)) return old
    }
}

// ── AtomicLong ─────────────────────────────────────────────────────────────

public fun AtomicLong.compareAndExchange(expectedValue: Long, newValue: Long): Long =
    __kkCompareAndExchange(expectedValue, newValue)

public fun AtomicLong.get(): Long = load()

public fun AtomicLong.set(value: Long): Unit = store(value)

public fun AtomicLong.getAndSet(newValue: Long): Long = exchange(newValue)

public fun AtomicLong.incrementAndGet(): Long = incrementAndFetch()

public fun AtomicLong.decrementAndGet(): Long = decrementAndFetch()

public fun AtomicLong.addAndGet(delta: Long): Long = addAndFetch(delta)

public fun AtomicLong.fetchAndAdd(delta: Long): Long = addAndFetch(delta) - delta

public fun AtomicLong.fetchAndIncrement(): Long = incrementAndFetch() - 1L

public fun AtomicLong.fetchAndDecrement(): Long = decrementAndFetch() + 1L

public fun AtomicLong.compareAndSet(expectedValue: Long, newValue: Long): Boolean =
    compareAndExchange(expectedValue, newValue) == expectedValue

public fun AtomicLong.getAndUpdate(transform: (Long) -> Long): Long {
    while (true) {
        val old = load()
        val newValue = transform(old)
        if (compareAndSet(old, newValue)) return old
    }
}

public fun AtomicLong.updateAndGet(transform: (Long) -> Long): Long {
    while (true) {
        val old = load()
        val newValue = transform(old)
        if (compareAndSet(old, newValue)) return newValue
    }
}

public fun AtomicLong.fetchAndUpdate(transform: (Long) -> Long): Long {
    while (true) {
        val old = load()
        val newValue = transform(old)
        if (compareAndSet(old, newValue)) return old
    }
}

// ── AtomicBoolean ──────────────────────────────────────────────────────────
// KSP-670/KSP-688: get/set/getAndSet and compareAndSet delegate to the
// load/store/exchange/compareAndExchange bridge members. The compareAndExchange
// operation remains the runtime CAS core (__kk_atomic_bool_*).

public fun AtomicBoolean.compareAndExchange(expectedValue: Boolean, newValue: Boolean): Boolean =
    __kkCompareAndExchange(expectedValue, newValue)

public fun AtomicBoolean.get(): Boolean = load()

public fun AtomicBoolean.set(value: Boolean): Unit = store(value)

public fun AtomicBoolean.getAndSet(newValue: Boolean): Boolean = exchange(newValue)

public fun AtomicBoolean.compareAndSet(expectedValue: Boolean, newValue: Boolean): Boolean =
    compareAndExchange(expectedValue, newValue) == expectedValue

public fun AtomicBoolean.getAndUpdate(transform: (Boolean) -> Boolean): Boolean {
    while (true) {
        val old = load()
        val newValue = transform(old)
        if (compareAndSet(old, newValue)) return old
    }
}

public fun AtomicBoolean.updateAndGet(transform: (Boolean) -> Boolean): Boolean {
    while (true) {
        val old = load()
        val newValue = transform(old)
        if (compareAndSet(old, newValue)) return newValue
    }
}

public fun AtomicBoolean.fetchAndUpdate(transform: (Boolean) -> Boolean): Boolean {
    while (true) {
        val old = load()
        val newValue = transform(old)
        if (compareAndSet(old, newValue)) return old
    }
}

// ── AtomicReference<T> ─────────────────────────────────────────────────────

public fun <T> AtomicReference<T>.compareAndExchange(expectedValue: T, newValue: T): T =
    __kkCompareAndExchange(expectedValue, newValue)

public fun <T> AtomicReference<T>.get(): T = load()

public fun <T> AtomicReference<T>.set(value: T): Unit = store(value)

public fun <T> AtomicReference<T>.getAndSet(newValue: T): T = exchange(newValue)

public fun <T> AtomicReference<T>.compareAndSet(expectedValue: T, newValue: T): Boolean =
    compareAndExchange(expectedValue, newValue) === expectedValue

public fun <T> AtomicReference<T>.getAndUpdate(transform: (T) -> T): T {
    while (true) {
        val old = load()
        val newValue = transform(old)
        if (compareAndSet(old, newValue)) return old
    }
}

public fun <T> AtomicReference<T>.updateAndGet(transform: (T) -> T): T {
    while (true) {
        val old = load()
        val newValue = transform(old)
        if (compareAndSet(old, newValue)) return newValue
    }
}

public fun <T> AtomicReference<T>.fetchAndUpdate(transform: (T) -> T): T {
    while (true) {
        val old = load()
        val newValue = transform(old)
        if (compareAndSet(old, newValue)) return old
    }
}

public fun <T> AtomicReference<T>.updateAndFetch(transform: (T) -> T): T {
    while (true) {
        val old = load()
        val newValue = transform(old)
        if (compareAndSet(old, newValue)) return newValue
    }
}

// ── java.util.concurrent.atomic.AtomicInteger ──────────────────────────────

public fun AtomicInteger.getAndUpdate(transform: (Int) -> Int): Int {
    while (true) {
        val old = load()
        val newValue = transform(old)
        if (compareAndSet(old, newValue)) return old
    }
}

public fun AtomicInteger.updateAndGet(transform: (Int) -> Int): Int {
    while (true) {
        val old = load()
        val newValue = transform(old)
        if (compareAndSet(old, newValue)) return newValue
    }
}

public fun AtomicInteger.fetchAndUpdate(transform: (Int) -> Int): Int {
    while (true) {
        val old = load()
        val newValue = transform(old)
        if (compareAndSet(old, newValue)) return old
    }
}
