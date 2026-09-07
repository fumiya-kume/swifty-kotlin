package kotlin

// KSP-813: Keep Byte companion constants source-backed. Byte is a compiler
// primitive, so extension properties provide the public Companion surface
// without a runtime bridge.
public val Byte.Companion.MAX_VALUE: Byte get() = 127

public val Byte.Companion.MIN_VALUE: Byte get() = -128

public val Byte.Companion.SIZE_BITS: Int get() = 8

public val Byte.Companion.SIZE_BYTES: Int get() = 1
