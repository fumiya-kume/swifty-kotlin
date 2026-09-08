package kotlin

// KSP-847: Keep Float companion constants source-backed. Float is a compiler
// primitive, so extension properties provide the public Companion surface
// without a runtime bridge.
public val Float.Companion.MAX_VALUE: Float get() = 3.4028235E38F

public val Float.Companion.MIN_VALUE: Float get() = 1.4E-45F

// Keep the exact IEEE-754 bit pattern explicit instead of relying on signed
// Float arithmetic across the raw ABI boundary.
public val Float.Companion.NEGATIVE_INFINITY: Float get() = fromBits(-8388608)

public val Float.Companion.NaN: Float get() = fromBits(2143289344)

public val Float.Companion.POSITIVE_INFINITY: Float get() = 1.0F / 0.0F

public val Float.Companion.SIZE_BITS: Int get() = 32

public val Float.Companion.SIZE_BYTES: Int get() = 4
