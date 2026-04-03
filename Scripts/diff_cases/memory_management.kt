import java.lang.Runtime
import java.lang.System

fun main() {
    val runtime = Runtime.getRuntime()

    val totalBefore = runtime.totalMemory()
    val freeBefore = runtime.freeMemory()
    val maxBefore = runtime.maxMemory()

    println(totalBefore > 0L)
    println(freeBefore >= 0L)
    println(maxBefore >= totalBefore)

    val buffer = ByteArray(1024) { it.toByte() }
    println(buffer.size == 1024)

    System.gc()

    val totalAfter = Runtime.getRuntime().totalMemory()
    val freeAfter = Runtime.getRuntime().freeMemory()
    val maxAfter = Runtime.getRuntime().maxMemory()

    println(totalAfter > 0L)
    println(freeAfter >= 0L)
    println(maxAfter >= totalAfter)
}
