package kotlin

// KSP-815: Keep Char companion constants source-backed. Char is a compiler
// primitive, so these extension properties provide the public stdlib surface
// without a runtime bridge.
public val Char.Companion.MAX_CODE_POINT: Int get() = 0x10FFFF

public val Char.Companion.MAX_HIGH_SURROGATE: Char get() = '\uDBFF'

public val Char.Companion.MAX_LOW_SURROGATE: Char get() = '\uDFFF'

public val Char.Companion.MAX_RADIX: Int get() = 36

public val Char.Companion.MAX_SURROGATE: Char get() = '\uDFFF'

public val Char.Companion.MAX_VALUE: Char get() = '\uFFFF'

public val Char.Companion.MIN_CODE_POINT: Int get() = 0

public val Char.Companion.MIN_HIGH_SURROGATE: Char get() = '\uD800'

public val Char.Companion.MIN_LOW_SURROGATE: Char get() = '\uDC00'

public val Char.Companion.MIN_RADIX: Int get() = 2

public val Char.Companion.MIN_SUPPLEMENTARY_CODE_POINT: Int get() = 0x10000

public val Char.Companion.MIN_SURROGATE: Char get() = '\uD800'

public val Char.Companion.MIN_VALUE: Char get() = '\u0000'

public val Char.Companion.SIZE_BITS: Int get() = 16

public val Char.Companion.SIZE_BYTES: Int get() = 2
