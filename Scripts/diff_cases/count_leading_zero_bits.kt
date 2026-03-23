fun main() {
    // Int.countLeadingZeroBits() edge cases
    println(0.countLeadingZeroBits())           // all zeros → 32
    println(1.countLeadingZeroBits())           // only LSB set → 31
    println((-1).countLeadingZeroBits())        // all ones → 0
    println(Int.MAX_VALUE.countLeadingZeroBits()) // 0x7FFFFFFF → 1
    println(Int.MIN_VALUE.countLeadingZeroBits()) // 0x80000000 → 0

    // Powers of two
    println(2.countLeadingZeroBits())           // 30
    println(4.countLeadingZeroBits())           // 29
    println(16.countLeadingZeroBits())          // 27
    println(256.countLeadingZeroBits())         // 23
    println(65536.countLeadingZeroBits())       // 15
    println(1073741824.countLeadingZeroBits())  // 2^30 → 1

    // Arbitrary values
    println(255.countLeadingZeroBits())         // 0xFF → 24
    println(1023.countLeadingZeroBits())        // 0x3FF → 22
    println(100.countLeadingZeroBits())         // 25

    // Negative values
    println((-2).countLeadingZeroBits())        // 0
    println((-128).countLeadingZeroBits())      // 0
    println((-2147483647).countLeadingZeroBits()) // 0

    // countTrailingZeroBits edge cases
    println(0.countTrailingZeroBits())          // all zeros → 32
    println(1.countTrailingZeroBits())          // 0
    println((-1).countTrailingZeroBits())       // 0
    println(Int.MIN_VALUE.countTrailingZeroBits()) // 31
    println(Int.MAX_VALUE.countTrailingZeroBits()) // 0
    println(16.countTrailingZeroBits())         // 4
    println(256.countTrailingZeroBits())        // 8

    // countOneBits edge cases
    println(0.countOneBits())                   // 0
    println(1.countOneBits())                   // 1
    println((-1).countOneBits())                // 32
    println(Int.MAX_VALUE.countOneBits())       // 31
    println(Int.MIN_VALUE.countOneBits())       // 1
    println(255.countOneBits())                 // 8
    println(0x55555555.countOneBits())          // 16
}
