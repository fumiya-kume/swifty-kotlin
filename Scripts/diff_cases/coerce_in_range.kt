fun main() {
    // Int.coerceIn(IntRange) — range literal
    println(5.coerceIn(1..10))
    println(0.coerceIn(1..10))
    println(15.coerceIn(1..10))

    // Long.coerceIn(LongRange) — range literal
    println(5L.coerceIn(1L..10L))
    println(0L.coerceIn(1L..10L))
    println(15L.coerceIn(1L..10L))

    // Precomputed range values stored in variables
    val intRange = 1..10
    println(5.coerceIn(intRange))
    println(0.coerceIn(intRange))
    println(15.coerceIn(intRange))

    val longRange = 1L..10L
    println(5L.coerceIn(longRange))
    println(0L.coerceIn(longRange))
    println(15L.coerceIn(longRange))

    // Nullable receiver safe-call
    val x: Int? = 5
    val y: Int? = null
    println(x?.coerceIn(1..10))
    println(y?.coerceIn(1..10))
}
