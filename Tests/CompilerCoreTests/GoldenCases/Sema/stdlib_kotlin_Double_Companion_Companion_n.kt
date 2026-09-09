package golden.sema

fun main() {
    val directMin: Double = Double.MIN_VALUE
    val directMax: Double = Double.MAX_VALUE
    val directPositiveInfinity: Double = Double.POSITIVE_INFINITY
    val directNegativeInfinity: Double = Double.NEGATIVE_INFINITY
    val directNaN: Double = Double.NaN
    val directBytes: Int = Double.SIZE_BYTES
    val directBits: Int = Double.SIZE_BITS
    val explicitMin: Double = Double.Companion.MIN_VALUE
    val explicitMax: Double = Double.Companion.MAX_VALUE
    val explicitPositiveInfinity: Double = Double.Companion.POSITIVE_INFINITY
    val explicitNegativeInfinity: Double = Double.Companion.NEGATIVE_INFINITY
    val explicitNaN: Double = Double.Companion.NaN
    val explicitBytes: Int = Double.Companion.SIZE_BYTES
    val explicitBits: Int = Double.Companion.SIZE_BITS
    println(directMin)
    println(directMax)
    println(directPositiveInfinity)
    println(directNegativeInfinity)
    println(directNaN)
    println(directBytes)
    println(directBits)
    println(explicitMin)
    println(explicitMax)
    println(explicitPositiveInfinity)
    println(explicitNegativeInfinity)
    println(explicitNaN)
    println(explicitBytes)
    println(explicitBits)
}
