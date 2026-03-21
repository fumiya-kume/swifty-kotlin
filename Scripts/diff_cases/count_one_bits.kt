fun main() {
    // Zero — no bits set
    println(0.countOneBits())

    // Int.MAX_VALUE — 31 bits set (0x7FFFFFFF)
    println(Int.MAX_VALUE.countOneBits())

    // Int.MIN_VALUE — only sign bit set (0x80000000)
    println(Int.MIN_VALUE.countOneBits())

    // -1 — all 32 bits set (0xFFFFFFFF)
    println((-1).countOneBits())

    // Powers of 2 — exactly 1 bit set each
    println(1.countOneBits())
    println(2.countOneBits())
    println(4.countOneBits())
    println(1024.countOneBits())

    // Alternating bit patterns
    // 0x55555555 = 0101...0101 (16 bits set)
    println(0x55555555.countOneBits())
    // 0x2AAAAAAA = 0010 1010...1010 (15 bits set, fits in positive Int)
    println(0x2AAAAAAA.countOneBits())

    // Small negative numbers
    println((-2).countOneBits())

    // Stored in variable
    val x: Int = 255
    println(x.countOneBits())

    // Expression receiver
    println((127 + 128).countOneBits())
}
