fun main() {
    // Long coercion functions
    val l: Long = 100L
    val lClamped: Long = l.coerceIn(0L, 200L)
    val lAtLeast: Long = l.coerceAtLeast(50L)
    val lAtMost: Long = l.coerceAtMost(150L)
    println(lClamped)
    println(lAtLeast)
    println(lAtMost)

    // Double coercion functions
    val d: Double = 3.14
    val dClamped: Double = d.coerceIn(0.0, 10.0)
    val dAtLeast: Double = d.coerceAtLeast(1.0)
    val dAtMost: Double = d.coerceAtMost(5.0)
    println(dClamped)
    println(dAtLeast)
    println(dAtMost)

    // Float coercion functions
    val f: Float = 2.5f
    val fClamped: Float = f.coerceIn(0.0f, 5.0f)
    val fAtLeast: Float = f.coerceAtLeast(1.0f)
    val fAtMost: Float = f.coerceAtMost(4.0f)
    println(fClamped)
    println(fAtLeast)
    println(fAtMost)

    // Int coercion functions (baseline)
    val i: Int = 42
    val iClamped: Int = i.coerceIn(0, 100)
    val iAtLeast: Int = i.coerceAtLeast(10)
    val iAtMost: Int = i.coerceAtMost(50)
    println(iClamped)
    println(iAtLeast)
    println(iAtMost)
}
