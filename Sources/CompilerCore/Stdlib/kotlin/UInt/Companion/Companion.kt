package kotlin

// KSP-907: Keep UInt companion constants source-backed. UInt is a compiler
// primitive, so these extension properties provide the public stdlib surface
// without a runtime bridge.
public val UInt.Companion.MAX_VALUE: UInt get() = 4294967295u

public val UInt.Companion.MIN_VALUE: UInt get() = 0u

public val UInt.Companion.SIZE_BITS: Int get() = 32

public val UInt.Companion.SIZE_BYTES: Int get() = 4
