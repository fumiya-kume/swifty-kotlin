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

    // Double coercion
    val d: Double = 3.14
    println(d.coerceIn(0.0, 10.0))
    println(d.coerceAtLeast(1.0))
    println(d.coerceAtMost(5.0))
    println((-1.5).coerceAtLeast(0.0))
    println(99.9.coerceAtMost(10.0))

    // Float coercion
    val f: Float = 2.5f
    println(f.coerceIn(0.0f, 5.0f))
    println(f.coerceAtLeast(1.0f))
    println(f.coerceAtMost(4.0f))
}
