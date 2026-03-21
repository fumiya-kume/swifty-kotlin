import kotlin.time.*
import kotlin.time.Duration.Companion.seconds
import kotlin.time.Duration.Companion.milliseconds
import kotlin.time.Duration.Companion.microseconds

fun main() {
    val d = 3.seconds
    println(d.inWholeMicroseconds)
    val d2 = 2500.milliseconds
    println(d2.inWholeMicroseconds)
    val d3 = 42.microseconds
    println(d3.inWholeMicroseconds)
}
