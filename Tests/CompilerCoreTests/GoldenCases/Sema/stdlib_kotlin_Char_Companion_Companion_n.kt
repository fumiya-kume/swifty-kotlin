package golden.sema

fun main() {
    val directMaxCodePoint: Int = Char.MAX_CODE_POINT
    val directMaxHighSurrogate: Char = Char.MAX_HIGH_SURROGATE
    val directMaxLowSurrogate: Char = Char.MAX_LOW_SURROGATE
    val directMaxRadix: Int = Char.MAX_RADIX
    val directMaxSurrogate: Char = Char.MAX_SURROGATE
    val directMaxValue: Char = Char.MAX_VALUE
    val directMinCodePoint: Int = Char.MIN_CODE_POINT
    val directMinHighSurrogate: Char = Char.MIN_HIGH_SURROGATE
    val directMinLowSurrogate: Char = Char.MIN_LOW_SURROGATE
    val directMinRadix: Int = Char.MIN_RADIX
    val directMinSupplementaryCodePoint: Int = Char.MIN_SUPPLEMENTARY_CODE_POINT
    val directMinSurrogate: Char = Char.MIN_SURROGATE
    val directMinValue: Char = Char.MIN_VALUE
    val directSizeBits: Int = Char.SIZE_BITS
    val directSizeBytes: Int = Char.SIZE_BYTES

    val explicitMaxCodePoint: Int = Char.Companion.MAX_CODE_POINT
    val explicitMaxHighSurrogate: Char = Char.Companion.MAX_HIGH_SURROGATE
    val explicitMaxLowSurrogate: Char = Char.Companion.MAX_LOW_SURROGATE
    val explicitMaxRadix: Int = Char.Companion.MAX_RADIX
    val explicitMaxSurrogate: Char = Char.Companion.MAX_SURROGATE
    val explicitMaxValue: Char = Char.Companion.MAX_VALUE
    val explicitMinCodePoint: Int = Char.Companion.MIN_CODE_POINT
    val explicitMinHighSurrogate: Char = Char.Companion.MIN_HIGH_SURROGATE
    val explicitMinLowSurrogate: Char = Char.Companion.MIN_LOW_SURROGATE
    val explicitMinRadix: Int = Char.Companion.MIN_RADIX
    val explicitMinSupplementaryCodePoint: Int = Char.Companion.MIN_SUPPLEMENTARY_CODE_POINT
    val explicitMinSurrogate: Char = Char.Companion.MIN_SURROGATE
    val explicitMinValue: Char = Char.Companion.MIN_VALUE
    val explicitSizeBits: Int = Char.Companion.SIZE_BITS
    val explicitSizeBytes: Int = Char.Companion.SIZE_BYTES

    println(directMaxCodePoint)
    println(directMaxHighSurrogate.code)
    println(directMaxLowSurrogate.code)
    println(directMaxRadix)
    println(directMaxSurrogate.code)
    println(directMaxValue.code)
    println(directMinCodePoint)
    println(directMinHighSurrogate.code)
    println(directMinLowSurrogate.code)
    println(directMinRadix)
    println(directMinSupplementaryCodePoint)
    println(directMinSurrogate.code)
    println(directMinValue.code)
    println(directSizeBits)
    println(directSizeBytes)

    println(explicitMaxCodePoint)
    println(explicitMaxHighSurrogate.code)
    println(explicitMaxLowSurrogate.code)
    println(explicitMaxRadix)
    println(explicitMaxSurrogate.code)
    println(explicitMaxValue.code)
    println(explicitMinCodePoint)
    println(explicitMinHighSurrogate.code)
    println(explicitMinLowSurrogate.code)
    println(explicitMinRadix)
    println(explicitMinSupplementaryCodePoint)
    println(explicitMinSurrogate.code)
    println(explicitMinValue.code)
    println(explicitSizeBits)
    println(explicitSizeBytes)
}
