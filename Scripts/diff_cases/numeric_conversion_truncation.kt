fun main() {
    // Int -> Byte truncation (low 8 bits, signed interpretation)
    println(200.toByte())
    println(255.toByte())
    println(256.toByte())
    println(1000.toByte())
    // Int -> Short truncation
    println(40000.toShort())
    println(70000.toShort())
    println(65536.toShort())
    // Long -> Int truncation
    println(4294967296L.toInt())
    println(4294967297L.toInt())
    println(Long.MAX_VALUE.toInt())
    println(Long.MIN_VALUE.toInt())
    // Widening / sign extension
    println((-1).toLong())
    println(Int.MIN_VALUE.toLong())
    val b: Byte = -1
    println(b.toInt())
    val s: Short = -1
    println(s.toInt())
    // Chained truncation
    println(1000.toByte().toInt())
    println(70000.toShort().toInt())
}
