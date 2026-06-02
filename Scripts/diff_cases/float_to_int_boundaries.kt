fun main() {
    // Double -> Int special values
    println(Double.NaN.toInt())
    println(Double.POSITIVE_INFINITY.toInt())
    println(Double.NEGATIVE_INFINITY.toInt())
    println(1e20.toInt())
    println((-1e20).toInt())
    // Double -> Int truncation toward zero
    println(3.99.toInt())
    println((-3.99).toInt())
    println(2.5.toInt())
    // Double -> Long special values / out of range
    println(Double.NaN.toLong())
    println(Double.POSITIVE_INFINITY.toLong())
    println(Double.NEGATIVE_INFINITY.toLong())
    println(1e30.toLong())
    println((-1e30).toLong())
    println(3.99.toLong())
    // Float -> Int
    println(Float.NaN.toInt())
    println(Float.POSITIVE_INFINITY.toInt())
    println(3.99f.toInt())
    println(1e20f.toInt())
    // Chained: Double -> Int -> Byte
    println(300.0.toInt().toByte())
    println(127.99.toInt())
}
