fun main() {
    val x: UInt = 42u
    val y: ULong = 42uL
    println(x.toInt())
    println(x.toUInt())
    println(x.toLong())
    println(x.toULong())
    println(y.toInt())
    println(100u / 3u)
    println(100u % 3u)
    println(255u and 15u)
    println(240u or 15u)
    println(255u xor 15u)
}
