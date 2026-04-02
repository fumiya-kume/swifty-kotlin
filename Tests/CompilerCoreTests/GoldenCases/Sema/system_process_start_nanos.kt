fun main() {
    val startNanos: Long = System.processStartNanos()
    val now: Long = System.nanoTime()
    println(startNanos > 0)
    println(now >= startNanos)
}
