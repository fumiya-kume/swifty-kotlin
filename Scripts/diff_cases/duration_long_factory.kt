import kotlin.time.*
import kotlin.time.Duration.Companion.seconds
import kotlin.time.Duration.Companion.milliseconds
import kotlin.time.Duration.Companion.minutes
import kotlin.time.Duration.Companion.hours
import kotlin.time.Duration.Companion.nanoseconds
import kotlin.time.Duration.Companion.microseconds

fun main() {
    val d1 = 5L.seconds
    println(d1.inWholeSeconds)
    println(d1.inWholeMilliseconds)

    val d2 = 2500L.milliseconds
    println(d2.inWholeSeconds)
    println(d2.inWholeMilliseconds)

    val d3 = 120L.minutes
    println(d3.inWholeMinutes)

    val d4 = 2L.hours
    println(d4.inWholeMinutes)

    val d5 = 5000000L.nanoseconds
    println(d5.inWholeNanoseconds)

    val d6 = 5000L.microseconds
    println(d6.inWholeMilliseconds)
}
