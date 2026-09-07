package kotlin.time

// KSP-1482: ComparableTimeMark equality and hash-code members.
//
// TimeMark operations remain bundled extensions in TimeMark.kt. These two
// declarations stay as interface members so interface-typed calls use the
// same virtual contract as Kotlin stdlib.
public interface ComparableTimeMark : TimeMark {
    public override fun equals(other: Any?): Boolean

    public override fun hashCode(): Int
}
