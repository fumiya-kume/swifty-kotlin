// IEEE-754 negative zero parity: unary minus must flip the sign bit so that
// -(0.0) == -0.0 (it must NOT be lowered as 0.0 - x, which yields +0.0).
fun main() {
    println(-0.0)
    println(-0.0f)
    val z = 0.0
    println(-z)
    val zf = 0.0f
    println(-zf)
    println(0.0 * -1.0)
    val nz = -0.0
    println(-nz)
    println(1.0 / -0.0)
}
