// SKIP-DIFF: kotlinc 2.3.10 treats Duration.isNegative/isPositive/isFinite/isInfinite as functions, not properties
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

    // STDLIB-TIME-082: advanced properties
    val neg = (-30).seconds
    println(neg.isNegative)
    println(neg.absoluteValue.inWholeSeconds)
    val pos = 10.seconds
    println(pos.isPositive)
    println(pos.isFinite)
    println(pos.isInfinite)

    // STDLIB-TIME-082: math operations
    val a = 30.seconds
    val b = 20.seconds
    val sum = a.plus(b)
    println(sum.inWholeSeconds)
    val diff = a.minus(b)
    println(diff.inWholeSeconds)
    val scaled = a.times(3)
    println(scaled.inWholeSeconds)
    val divided = a.div(2)
    println(divided.inWholeSeconds)
    val negated = a.unaryMinus()
    println(negated.isNegative)
    val cmp = a.compareTo(b)
    println(cmp > 0)
}
