package kotlin.time

// KSP-649
// TimeSource / TimeSource.WithComparableMarks / TimeSource.Monotonic and the new
// TimeSource.Monotonic.ValueTimeMark value class.
//
// The monotonic clock reading stays native: __kk_time_source_monotonic_mark_now
// samples the monotonic clock, and the Kotlin source wraps the reading in a
// ValueTimeMark. __kk_time_source_as_clock builds a Clock backed by a time source.
//
// TimeMark and ComparableTimeMark are migrated to marker interfaces; their
// operations remain extension functions in kotlin/time/TimeMark.kt.

import kotlin.internal.KsSymbolName
import kotlin.contracts.ExperimentalContracts
import kotlin.contracts.contract

@KsSymbolName("__kk_time_source_monotonic_mark_now")
private external fun __kk_time_source_monotonic_mark_now(receiver: Long): Long

@KsSymbolName("__kk_time_source_as_clock")
public external fun TimeSource.asClock(origin: Instant): Clock

public interface TimeSource {
    public fun markNow(): TimeMark

    public interface WithComparableMarks : TimeSource {
        public override fun markNow(): ComparableTimeMark
    }

    public object Monotonic : TimeSource.WithComparableMarks {
        public override fun markNow(): ValueTimeMark =
            ValueTimeMark(__kk_time_source_monotonic_mark_now(0L))

        public override fun toString(): String = "Monotonic"

        @JvmInline
        public value class ValueTimeMark internal constructor(internal val reading: Long) : ComparableTimeMark {
            public fun elapsedNow(): Duration =
                timeMarkElapsedNanos(reading).nanoseconds

            public operator fun plus(duration: Duration): ValueTimeMark =
                ValueTimeMark(timeMarkAddNanos(reading, duration.inWholeNanoseconds))

            public operator fun minus(duration: Duration): ValueTimeMark =
                plus(-duration)

            public override fun hasPassedNow(): Boolean = !elapsedNow().isNegative()

            public override fun hasNotPassedNow(): Boolean = elapsedNow().isNegative()

            public override operator fun minus(other: ComparableTimeMark): Duration {
                if (other !is ValueTimeMark) {
                    throw IllegalArgumentException(
                        "Subtracting or comparing time marks from different time sources is not possible: $this and $other"
                    )
                }
                val valueTimeMark = other as ValueTimeMark
                return this.minus(valueTimeMark)
            }

            public operator fun compareTo(other: ValueTimeMark): Int =
                reading.compareTo(other.reading)

            public operator fun minus(other: ValueTimeMark): Duration =
                timeMarkAddNanos(reading, timeMarkNegateNanos(other.reading)).nanoseconds

            public override fun equals(other: Any?): Boolean {
                if (other !is ValueTimeMark) return false
                val that = other as ValueTimeMark
                return reading == that.reading
            }

            public override fun hashCode(): Int =
                reading.toInt() xor (reading ushr 32).toInt()

            public override fun toString(): String = "ValueTimeMark(reading=$reading)"
        }
    }

    public companion object {
    }
}

// KSP-1475
// Measure an interval with the receiver's time source. The mark is captured
// before invoking the block so the result includes the complete block body.
@OptIn(ExperimentalContracts::class)
public inline fun TimeSource.measureTime(block: () -> Unit): Duration {
    contract {
        callsInPlace(block, kotlin.contracts.InvocationKind.EXACTLY_ONCE)
    }
    val mark = markNow()
    block()
    return mark.elapsedNow()
}

// KSP-1475
// Preserve the value produced by the block while measuring against the same
// receiver mark. TimedValue's synthetic constructor supplies the existing
// runtime allocation ABI without adding a new bridge for this source API.
@OptIn(ExperimentalContracts::class)
public inline fun <T> TimeSource.measureTimedValue(block: () -> T): TimedValue<T> {
    contract {
        callsInPlace(block, kotlin.contracts.InvocationKind.EXACTLY_ONCE)
    }
    val mark = markNow()
    val result = block()
    return TimedValue(result, mark.elapsedNow())
}
