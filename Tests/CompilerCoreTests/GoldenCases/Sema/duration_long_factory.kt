import kotlin.time.*
import kotlin.time.Duration.Companion.seconds
import kotlin.time.Duration.Companion.milliseconds

fun main() {
    val d1 = 5L.seconds
    println(d1.inWholeSeconds)
    val d2 = 2500L.milliseconds
    println(d2.inWholeMilliseconds)
}
