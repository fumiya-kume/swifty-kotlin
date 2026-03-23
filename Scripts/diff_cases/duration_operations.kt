import kotlin.time.Duration.Companion.seconds
import kotlin.time.Duration.Companion.milliseconds
import kotlin.time.Duration.Companion.minutes
import kotlin.time.Duration.Companion.hours

fun main() {
    val d = 90.seconds
    println(d.inWholeSeconds)
    println(d.inWholeMilliseconds)
    println(d.inWholeMinutes)
    println(d.toString())
    val d2 = 2.hours
    println(d2.inWholeMinutes)
    println(d2.inWholeSeconds)
    println(d2.inWholeHours)
    val d3 = 500.milliseconds
    println(d3.inWholeMilliseconds)
    println(d3.inWholeSeconds)
}
