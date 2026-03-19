fun main() {
    // Int.coerceIn(IntRange) — range literal
    println(5.coerceIn(1..10))
    println(0.coerceIn(1..10))
    println(15.coerceIn(1..10))

    // Long.coerceIn(LongRange) — range literal
    println(5L.coerceIn(1L..10L))
    println(0L.coerceIn(1L..10L))
    println(15L.coerceIn(1L..10L))

    // Nullable receiver safe-call
    val x: Int? = 5
    val y: Int? = null
    println(x?.coerceIn(1..10))
    println(y?.coerceIn(1..10))
}
