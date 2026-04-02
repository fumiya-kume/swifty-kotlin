// SKIP-DIFF: System.processStartNanos() is not yet available in kotlinc.
fun main() {
    val startNanos = System.processStartNanos()
    val now = System.nanoTime()
    // processStartNanos must be positive and no greater than current nanoTime
    println(startNanos > 0)
    println(now >= startNanos)
}
