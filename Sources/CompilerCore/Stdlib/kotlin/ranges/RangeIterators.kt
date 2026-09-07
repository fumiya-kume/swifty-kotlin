package kotlin.ranges

// MIGRATION-RANGE-001
// iterator() for IntRange, LongRange, CharRange, UIntRange, IntProgression,
// LongProgression, CharProgression, and UIntProgression.
// Migration source: Sources/Runtime/RuntimeRangeAndDispatch.swift
//   (kk_range_iterator, kk_range_hasNext, kk_range_next)
//   Sources/Runtime/RuntimeRangeLongRange.swift (kk_long_range_iterator)
//   Sources/Runtime/RuntimeRangeUIntULongRange.swift
//   (__kk_uint_range_iterator, __kk_uint_range_hasNext, __kk_uint_range_next)
// See RangeMembership.kt for the contains()/isEmpty() half of this migration.
//
// KSP-452 removed the `for (x in range)` lowering special case, so plain range
// loops now go through these operators like every other iterable.
//
// The iterators below step lazily instead of materialising every element (the
// earlier toList()-based shape was O(n) memory and made large loops unusable).
// hasNext is recomputed from the *next* value rather than compared against
// `last`, so a progression whose `last` was not snapped onto the step grid
// (e.g. 1..9 step 3) still stops at the final in-range element, and the
// monotonicity check keeps the step past the final element from wrapping around
// at Int/Long boundaries.
//
// A zero step means "empty": the runtime range representation marks an empty
// `a until b` (b <= a) with step 0 rather than with first/last bounds that
// exclude each other (__kk_op_rangeUntil in RuntimeRangeAndDispatch.swift).

internal class IntProgressionIterator(first: Int, last: Int, private val step: Int) : Iterator<Int> {
    private val finalElement: Int = last
    private var nextValue: Int = first
    private var hasNextValue: Boolean = if (step > 0) first <= last else if (step < 0) first >= last else false

    override fun hasNext(): Boolean = hasNextValue

    override fun next(): Int {
        val value = nextValue
        val candidate = value + step
        hasNextValue = if (step > 0) candidate > value && candidate <= finalElement else candidate < value && candidate >= finalElement
        nextValue = candidate
        return value
    }
}

internal class LongProgressionIterator(first: Long, last: Long, private val step: Long) : Iterator<Long> {
    private val finalElement: Long = last
    private var nextValue: Long = first
    private var hasNextValue: Boolean = if (step > 0L) first <= last else if (step < 0L) first >= last else false

    override fun hasNext(): Boolean = hasNextValue

    override fun next(): Long {
        val value = nextValue
        val candidate = value + step
        hasNextValue = if (step > 0L) candidate > value && candidate <= finalElement else candidate < value && candidate >= finalElement
        nextValue = candidate
        return value
    }
}

internal class CharProgressionIterator(first: Char, last: Char, private val step: Int) : Iterator<Char> {
    private val finalElement: Char = last
    private var nextValue: Char = first
    private var hasNextValue: Boolean = if (step > 0) first <= last else if (step < 0) first >= last else false

    override fun hasNext(): Boolean = hasNextValue

    override fun next(): Char {
        val value = nextValue
        val candidate = value + step
        hasNextValue = if (step > 0) candidate > value && candidate <= finalElement else candidate < value && candidate >= finalElement
        nextValue = candidate
        return value
    }
}

public operator fun IntRange.iterator(): Iterator<Int> = IntProgressionIterator(this.first, this.last, this.step)
public operator fun IntProgression.iterator(): Iterator<Int> = IntProgressionIterator(this.first, this.last, this.step)
public operator fun LongRange.iterator(): Iterator<Long> = LongProgressionIterator(this.first, this.last, this.step)
// LongProgression.step is modelled as Int (LongRange.step is Long); widen it here.
public operator fun LongProgression.iterator(): Iterator<Long> = LongProgressionIterator(this.first, this.last, this.step.toLong())
public operator fun CharRange.iterator(): Iterator<Char> = CharProgressionIterator(this.first, this.last, this.step)
public operator fun CharProgression.iterator(): Iterator<Char> = CharProgressionIterator(this.first, this.last, this.step)

internal class UIntProgressionIterator(first: UInt, last: UInt, private val step: Int) : Iterator<UInt> {
    private val finalElement: UInt = last
    private var nextValue: UInt = first
    private var hasNextValue: Boolean = if (step > 0) first <= last else if (step < 0) first >= last else false

    override fun hasNext(): Boolean = hasNextValue

    override fun next(): UInt {
        val value = nextValue
        val candidate = value + step.toUInt()
        hasNextValue = if (step > 0) candidate > value && candidate <= finalElement else candidate < value && candidate >= finalElement
        nextValue = candidate
        return value
    }
}

internal class ULongProgressionIterator(first: ULong, last: ULong, private val step: Int) : Iterator<ULong> {
    private val finalElement: ULong = last
    private var nextValue: ULong = first
    private var hasNextValue: Boolean = if (step > 0L) first <= last else if (step < 0L) first >= last else false

    override fun hasNext(): Boolean = hasNextValue

    override fun next(): ULong {
        val value = nextValue
        val candidate = value + step.toULong()
        hasNextValue = if (step > 0L) candidate > value && candidate <= finalElement else candidate < value && candidate >= finalElement
        nextValue = candidate
        return value
    }
}

public operator fun UIntRange.iterator(): Iterator<UInt> = UIntProgressionIterator(this.first, this.last, this.step)
public operator fun UIntProgression.iterator(): Iterator<UInt> = UIntProgressionIterator(this.first, this.last, this.step)
public operator fun ULongRange.iterator(): Iterator<ULong> = ULongProgressionIterator(this.first, this.last, this.step)
public operator fun ULongProgression.iterator(): Iterator<ULong> = ULongProgressionIterator(this.first, this.last, this.step)
