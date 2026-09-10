fun main() {
    val ordinary = -2..2
    println(ordinary.contains((-2).toByte()))
    println((-3).toByte() in ordinary)
    println(ordinary.contains((-2).toShort()))
    println(3.toShort() in ordinary)
    println(ordinary.contains(-2L))
    println(3L in ordinary)

    val full = Int.MIN_VALUE..Int.MAX_VALUE
    println(full.contains(Byte.MIN_VALUE))
    println(Byte.MAX_VALUE in full)
    println(full.contains(Short.MIN_VALUE))
    println(Short.MAX_VALUE in full)
    println(full.contains(Int.MIN_VALUE.toLong()))
    println(Int.MAX_VALUE.toLong() in full)
    println(full.contains(Int.MIN_VALUE.toLong() - 1L))
    println((Int.MAX_VALUE.toLong() + 1L) in full)

    val empty = 3..2
    println(empty.contains(Byte.MIN_VALUE))
    println(Byte.MAX_VALUE in empty)
    println(empty.contains(Short.MIN_VALUE))
    println(Short.MAX_VALUE in empty)
    println(empty.contains(Int.MIN_VALUE.toLong() - 1L))
    println((Int.MAX_VALUE.toLong() + 1L) in empty)
}
