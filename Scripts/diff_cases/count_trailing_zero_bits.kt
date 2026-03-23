fun main() {
    // Zero: all 32 bits are zero
    println(0.countTrailingZeroBits())

    // One: no trailing zeros
    println(1.countTrailingZeroBits())

    // -1: all bits set in two's complement
    println((-1).countTrailingZeroBits())

    // Int.MIN_VALUE: only MSB set (bit 31)
    println(Int.MIN_VALUE.countTrailingZeroBits())

    // Int.MAX_VALUE: all bits set except MSB
    println(Int.MAX_VALUE.countTrailingZeroBits())

    // Powers of two
    println(2.countTrailingZeroBits())
    println(4.countTrailingZeroBits())
    println(8.countTrailingZeroBits())
    println(16.countTrailingZeroBits())
    println(256.countTrailingZeroBits())
    println(1024.countTrailingZeroBits())

    // Large power of two
    println(1073741824.countTrailingZeroBits())

    // Arbitrary values
    println(6.countTrailingZeroBits())
    println(12.countTrailingZeroBits())
    println(48.countTrailingZeroBits())
    println((-2).countTrailingZeroBits())
    println((-128).countTrailingZeroBits())

    // Variable test
    val x: Int = 64
    println(x.countTrailingZeroBits())
}
