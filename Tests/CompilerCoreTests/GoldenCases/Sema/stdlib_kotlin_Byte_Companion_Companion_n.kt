package golden.sema

fun main() {
    val directMax: Byte = Byte.MAX_VALUE
    val directMin: Byte = Byte.MIN_VALUE
    val directBits: Int = Byte.SIZE_BITS
    val directBytes: Int = Byte.SIZE_BYTES
    val explicitMax: Byte = Byte.Companion.MAX_VALUE
    val explicitMin: Byte = Byte.Companion.MIN_VALUE
    val explicitBits: Int = Byte.Companion.SIZE_BITS
    val explicitBytes: Int = Byte.Companion.SIZE_BYTES
    val maxRoundTrip: Byte = Byte.MAX_VALUE.toByte()
    val minRoundTrip: Byte = Byte.MIN_VALUE.toByte()
    val bitProduct: Int = Byte.SIZE_BITS * Byte.SIZE_BYTES
    val boxedMax: Any = directMax
    val boxedMin: Any = directMin
    val maxIsByte: Boolean = boxedMax is Byte
    val minIsByte: Boolean = boxedMin is Byte
    println(directMax)
    println(directMin)
    println(directBits)
    println(directBytes)
    println(explicitMax)
    println(explicitMin)
    println(explicitBits)
    println(explicitBytes)
    println(bitProduct)
    println(maxIsByte)
    println(minIsByte)
}
