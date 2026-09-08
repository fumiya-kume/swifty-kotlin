package golden.sema

fun main() {
    val directMax: Float = Float.MAX_VALUE
    val directMin: Float = Float.MIN_VALUE
    val directNegativeInfinity: Float = Float.NEGATIVE_INFINITY
    val directNaN: Float = Float.NaN
    val directPositiveInfinity: Float = Float.POSITIVE_INFINITY
    val directBits: Int = Float.SIZE_BITS
    val directBytes: Int = Float.SIZE_BYTES
    val receiverMax: Float = Float.Companion.MAX_VALUE
    val receiverMin: Float = Float.Companion.MIN_VALUE
    val receiverNegativeInfinity: Float = Float.Companion.NEGATIVE_INFINITY
    val receiverNaN: Float = Float.Companion.NaN
    val receiverPositiveInfinity: Float = Float.Companion.POSITIVE_INFINITY
    val receiverBits: Int = Float.Companion.SIZE_BITS
    val receiverBytes: Int = Float.Companion.SIZE_BYTES
    println(directMax)
    println(directMin)
    println(directNegativeInfinity)
    println(directNaN)
    println(directPositiveInfinity)
    println(directBits)
    println(directBytes)
    println(receiverMax)
    println(receiverMin)
    println(receiverNegativeInfinity)
    println(receiverNaN)
    println(receiverPositiveInfinity)
    println(receiverBits)
    println(receiverBytes)
}
