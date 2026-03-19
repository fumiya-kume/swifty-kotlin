import kotlin.time.*
import kotlin.time.Duration.Companion.seconds
import kotlin.time.Duration.Companion.milliseconds

fun main() {
    val d = 90.seconds
    println(d.inWholeSeconds)
    println(d.inWholeMilliseconds)
    println(d.inWholeMinutes)
    val d2 = 2500.milliseconds
    println(d2.inWholeSeconds)
    println(d2.inWholeMilliseconds)
}
