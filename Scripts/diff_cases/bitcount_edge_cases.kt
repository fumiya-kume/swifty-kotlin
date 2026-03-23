fun main() {
    // countOneBits
    println(0.countOneBits())
    println(1.countOneBits())
    println((-1).countOneBits())
    println(Int.MAX_VALUE.countOneBits())
    println(Int.MIN_VALUE.countOneBits())
    println(0x55555555.countOneBits())

    // countLeadingZeroBits
    println(0.countLeadingZeroBits())
    println(1.countLeadingZeroBits())
    println((-1).countLeadingZeroBits())
    println(Int.MAX_VALUE.countLeadingZeroBits())
    println(Int.MIN_VALUE.countLeadingZeroBits())

    // countTrailingZeroBits
    println(0.countTrailingZeroBits())
    println(1.countTrailingZeroBits())
    println((-1).countTrailingZeroBits())
    println(Int.MAX_VALUE.countTrailingZeroBits())
    println(Int.MIN_VALUE.countTrailingZeroBits())
    println(16.countTrailingZeroBits())
}
