package kotlin

// KSP-833: Keep Double companion constants source-backed. Double is a compiler
// primitive, so these extension properties provide the public Companion
// surface without a runtime bridge.
public val Double.Companion.MIN_VALUE: Double get() = 4.9E-324

public val Double.Companion.MAX_VALUE: Double get() = 1.7976931348623157E308

public val Double.Companion.POSITIVE_INFINITY: Double get() = 1.0 / 0.0

public val Double.Companion.NEGATIVE_INFINITY: Double get() = -1.0 / 0.0

// 0.0 / 0.0 yields the platform's hardware NaN (negative quiet NaN on x86,
// positive on arm64); Kotlin pins the canonical positive quiet NaN, so the
// bit pattern is fixed explicitly to match kotlinc's toRawBits output.
public val Double.Companion.NaN: Double get() = fromBits(9221120237041090560L)

public val Double.Companion.SIZE_BYTES: Int get() = 8

public val Double.Companion.SIZE_BITS: Int get() = 64
