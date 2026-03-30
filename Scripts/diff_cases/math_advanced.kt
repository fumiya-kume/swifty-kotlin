import kotlin.math.*

fun main() {
    // atan2(y, x) — angle from x-axis to point (x, y)
    // atan2(1.0, 1.0) should be PI/4
    val a1: Double = atan2(1.0, 1.0)
    println(a1)

    // atan2(0.0, -1.0) should be PI
    val a2: Double = atan2(0.0, -1.0)
    println(a2)

    // hypot(3.0, 4.0) == 5.0
    val h1: Double = hypot(3.0, 4.0)
    println(h1)

    // hypot(0.0, 0.0) == 0.0
    val h2: Double = hypot(0.0, 0.0)
    println(h2)

    // coerceIn — value within range stays unchanged
    val c1: Int = 5.coerceIn(1, 10)
    println(c1)

    // coerceIn — value above max clamped to max
    val c2: Int = 15.coerceIn(1, 10)
    println(c2)

    // coerceIn — value below min clamped to min
    val c3: Int = (-5).coerceIn(1, 10)
    println(c3)

    // coerceAtLeast — value below min raised to min
    val c4: Int = 0.coerceAtLeast(5)
    println(c4)

    // coerceAtMost — value above max lowered to max
    val c5: Int = 20.coerceAtMost(10)
    println(c5)

    // maxOf with 3 arguments
    val mx1: Int = maxOf(1, 2, 3)
    println(mx1)

    val mx2: Int = maxOf(10, 3, 7)
    println(mx2)

    // minOf with 3 arguments
    val mn1: Int = minOf(1, 2, 3)
    println(mn1)

    val mn2: Int = minOf(10, 3, 7)
    println(mn2)
}
