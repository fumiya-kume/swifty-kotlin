fun main() {
    val directMax: ULong = ULong.MAX_VALUE
    val directMin: ULong = ULong.MIN_VALUE
    val directBits: Int = ULong.SIZE_BITS
    val directBytes: Int = ULong.SIZE_BYTES
    val explicitMax: ULong = ULong.Companion.MAX_VALUE
    val explicitMin: ULong = ULong.Companion.MIN_VALUE
    val explicitBits: Int = ULong.Companion.SIZE_BITS
    val explicitBytes: Int = ULong.Companion.SIZE_BYTES
    val highBitBoundary: ULong = 9223372036854775808uL
    val bitProduct: Int = ULong.SIZE_BITS * ULong.SIZE_BYTES
    val boxedMax: Any = directMax
    val boxedHighBit: Any = highBitBoundary
    println(directMax)
    println(directMin)
    println(directBits)
    println(directBytes)
    println(explicitMax)
    println(explicitMin)
    println(explicitBits)
    println(explicitBytes)
    println(highBitBoundary)
    println(bitProduct)
    println(boxedMax is ULong)
    println(boxedHighBit is ULong)
}
