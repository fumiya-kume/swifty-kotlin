// SKIP-DIFF: bit-manipulation runtime parity is still being stabilized; covered by RuntimeBitCountTests
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

    // STDLIB-BIT-007: Additional bit manipulation functions

    // rotateLeft
    println(1.rotateLeft(1))
    println(1.rotateLeft(31))
    println((-1).rotateLeft(5))
    println(Int.MAX_VALUE.rotateLeft(1))
    println(Int.MIN_VALUE.rotateLeft(1))
    println(0x80000001.rotateLeft(1))

    // rotateRight
    println(1.rotateRight(1))
    println(1.rotateRight(31))
    println((-1).rotateRight(5))
    println(Int.MAX_VALUE.rotateRight(1))
    println(Int.MIN_VALUE.rotateRight(1))
    println(0x80000001.rotateRight(1))

    // takeHighestOneBit
    println(0.takeHighestOneBit())
    println(1.takeHighestOneBit())
    println((-1).takeHighestOneBit())
    println(Int.MAX_VALUE.takeHighestOneBit())
    println(Int.MIN_VALUE.takeHighestOneBit())
    println(0x12345678.takeHighestOneBit())

    // takeLowestOneBit
    println(0.takeLowestOneBit())
    println(1.takeLowestOneBit())
    println((-1).takeLowestOneBit())
    println(Int.MAX_VALUE.takeLowestOneBit())
    println(Int.MIN_VALUE.takeLowestOneBit())
    println(0x12345678.takeLowestOneBit())

    // Long versions (64-bit tests)
    println(1L.rotateLeft(1))
    println(1L.rotateRight(1))
    println(1L.takeHighestOneBit())
    println(1L.takeLowestOneBit())
    println(Long.MAX_VALUE.rotateLeft(1))
    println(Long.MIN_VALUE.rotateLeft(1))
}
