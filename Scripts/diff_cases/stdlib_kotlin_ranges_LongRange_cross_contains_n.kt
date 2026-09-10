fun main() {
    val normal = -2L..2L
    println(normal.contains(Byte.MIN_VALUE))
    println(normal.contains((-2).toByte()))
    println(normal.contains(2))
    println(normal.contains(3))
    println(normal.contains(Short.MIN_VALUE))
    println(normal.contains(2.toShort()))

    println(Byte.MIN_VALUE in Long.MIN_VALUE..Long.MAX_VALUE)
    println(Int.MAX_VALUE in Long.MIN_VALUE..Long.MAX_VALUE)
    println(Short.MAX_VALUE in Long.MIN_VALUE..Long.MAX_VALUE)

    val empty = 5L..0L
    println(empty.contains(5.toByte()))
    println(5 in empty)
    println(5.toShort() in empty)
}
