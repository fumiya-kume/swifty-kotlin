package golden.sema

fun main() {
    val values = uintArrayOf(1u, 2147483648u, 4294967295u)
    val divisor = 17u
    println(values.size)
    println(values[1] / divisor)
    println(values[2] % divisor)
    println(values[2] > values[0])
    println(values[2].toLong())
    println(values[2].toULong())
    println(values[2].toFloat())
    println(values[2].toDouble())
}
