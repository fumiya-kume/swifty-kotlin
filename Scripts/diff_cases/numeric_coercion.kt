fun main() {
    // Int coercion (existing)
    println(15.coerceIn(1, 10))
    println(5.coerceIn(1, 10))
    println(0.coerceIn(1, 10))
    println(5.coerceAtLeast(10))
    println(15.coerceAtLeast(10))
    println(5.coerceAtMost(10))
    println(15.coerceAtMost(10))

    // Long coercion
    val l: Long = 100L
    println(l.coerceIn(0L, 200L))
    println(l.coerceAtLeast(50L))
    println(l.coerceAtMost(150L))
    println((-5L).coerceAtLeast(0L))
    println(999L.coerceAtMost(100L))
}
