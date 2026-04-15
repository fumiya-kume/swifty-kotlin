fun main() {
    println((1..4).toList())
    println((5 downTo 1 step 2).toList())
    println((1..0).toList())

    println(3.coerceIn(1, 5))
    println(0.coerceIn(1, 5))
    println(9.coerceIn(1, 5))

    println(3.coerceAtLeast(5))
    println(8.coerceAtMost(5))
}
