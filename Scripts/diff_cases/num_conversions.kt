// Numeric conversions parity with kotlinc: Long->Int truncation, Double->Int/Long
// (round-toward-zero with NaN->0 and saturation at the type bounds), Int->Byte/Short
// narrowing, Char<->Int, and Int/Long->Float/Double widening (with precision loss).
fun main() {
    println(4294967296L.toInt())
    println(4294967297L.toInt())
    println((-1L).toInt())
    println(Long.MAX_VALUE.toInt())

    println(3.9.toInt())
    println((-3.9).toInt())
    println(2.5e9.toInt())
    println((-2.5e9).toInt())
    println(Double.NaN.toInt())
    println(Double.POSITIVE_INFINITY.toInt())
    println(Double.NEGATIVE_INFINITY.toInt())
    println(Double.MAX_VALUE.toInt())

    println(3.9.toLong())
    println(Double.NaN.toLong())
    println(Double.POSITIVE_INFINITY.toLong())
    println(1e30.toLong())

    println(300.toByte())
    println(128.toByte())
    println((-129).toByte())
    println(65536.toShort())
    println(40000.toShort())

    println('A'.code)
    println(65.toChar())
    println(97.toChar())

    println(16777217.toFloat())
    println(Int.MAX_VALUE.toFloat())
    println(Long.MAX_VALUE.toDouble())
}
