fun main() {
    println(5L.coerceAtLeast(3L))
    println(1L.coerceAtLeast(3L))
    println(5L.coerceAtMost(3L))
    println(1L.coerceAtMost(3L))
    println(Long.MAX_VALUE.coerceAtLeast(0L))
    println(Long.MIN_VALUE.coerceAtMost(0L))
    println(100L.coerceIn(0L, 50L))
    println((-1L).coerceIn(0L, 50L))
    println(25L.coerceIn(0L, 50L))
    println(0L.coerceIn(0L, 50L))
    println(50L.coerceIn(0L, 50L))
}
