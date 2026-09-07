package kotlin

// KSP-910: Keep ULong companion constants source-backed. ULong is a compiler
// primitive, so extension properties provide the public Companion surface
// without a runtime bridge.
public val ULong.Companion.MAX_VALUE: ULong get() = 18446744073709551615uL

public val ULong.Companion.MIN_VALUE: ULong get() = 0uL

public val ULong.Companion.SIZE_BITS: Int get() = 64

public val ULong.Companion.SIZE_BYTES: Int get() = 8
