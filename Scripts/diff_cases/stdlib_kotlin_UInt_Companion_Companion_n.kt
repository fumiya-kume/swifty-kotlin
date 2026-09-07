fun main() {
    val directMax: UInt = UInt.MAX_VALUE
    val directMin: UInt = UInt.MIN_VALUE
    val directBits: Int = UInt.SIZE_BITS
    val directBytes: Int = UInt.SIZE_BYTES
    val receiverMax: UInt = UInt.Companion.MAX_VALUE
    val receiverMin: UInt = UInt.Companion.MIN_VALUE
    val receiverBits: Int = UInt.Companion.SIZE_BITS
    val receiverBytes: Int = UInt.Companion.SIZE_BYTES
    val maxWrap: UInt = UInt.MAX_VALUE + 1u
    val minWrap: UInt = UInt.MIN_VALUE - 1u
    val maxBoundary: Boolean = UInt.MAX_VALUE == 4294967295u
    val minBoundary: Boolean = UInt.MIN_VALUE == 0u
    println(directMax)
    println(directMin)
    println(directBits)
    println(directBytes)
    println(receiverMax)
    println(receiverMin)
    println(receiverBits)
    println(receiverBytes)
    println(maxWrap)
    println(minWrap)
    println(maxBoundary)
    println(minBoundary)
}
