fun main() {
    println(Float.MAX_VALUE.toRawBits() == 2139095039)
    println(Float.MIN_VALUE.toRawBits() == 1)
    println(Float.NEGATIVE_INFINITY.toRawBits() == -8388608)
    println(Float.NaN.toRawBits() == 2143289344)
    println(Float.NaN.toBits() == 2143289344)
    println(Float.POSITIVE_INFINITY.toRawBits() == 2139095040)
    println(Float.SIZE_BITS == 32)
    println(Float.SIZE_BYTES == 4)

    println(Float.Companion.MAX_VALUE.toRawBits() == 2139095039)
    println(Float.Companion.MIN_VALUE.toRawBits() == 1)
    println(Float.Companion.NEGATIVE_INFINITY.toRawBits() == -8388608)
    println(Float.Companion.NaN.toRawBits() == 2143289344)
    println(Float.Companion.NaN.toBits() == 2143289344)
    println(Float.Companion.POSITIVE_INFINITY.toRawBits() == 2139095040)
    println(Float.Companion.SIZE_BITS == 32)
    println(Float.Companion.SIZE_BYTES == 4)
}
