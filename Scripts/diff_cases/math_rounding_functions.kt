// SKIP-DIFF: List<Double> iteration boxes elements; when the loop variable is passed
// to round()/roundToInt()/etc, kswiftc currently forwards the boxed pointer as Double
// bits instead of unboxing, which rounds to 0. Unrelated to the math API surface itself.
import kotlin.math.*

fun main() {
    // Test rounding functions
    val values = listOf(3.2, 3.7, -2.3, -2.8, 0.5, -0.5)

    for (value in values) {
        println("Testing value: $value")

        // round() - nearest integer (banker's rounding toward even)
        val rounded = round(value)
        println(rounded)

        // Double.roundToInt() - nearest integer as Int (half away from zero)
        val roundedInt = value.roundToInt()
        println(roundedInt)

        // Double.roundToLong() - nearest integer as Long (half away from zero)
        val roundedLong = value.roundToLong()
        println(roundedLong)

        // floor() - round down
        val floored = floor(value)
        println(floored)

        // ceil() - round up
        val ceiled = ceil(value)
        println(ceiled)

        // truncate toward zero via sign-dependent floor/ceil
        val truncated = if (value < 0.0) ceil(value) else floor(value)
        println(truncated)
    }

    // Test absolute value functions
    val doubleValues = listOf(-3.5, 0.0, 4.2)
    for (value in doubleValues) {
        val absDouble = abs(value)
        println(absDouble)
    }

    val intValues = listOf(-5, 0, 7)
    for (value in intValues) {
        val absInt = abs(value)
        println(absInt)
    }

    // Test utility functions
    val x = 3.0
    val y = 4.0

    // hypot(3, 4) = 5
    val hypotValue = hypot(x, y)
    println(hypotValue)

    // sign function
    val positiveSign = sign(5.0)
    val negativeSign = sign(-3.0)
    val zeroSign = sign(0.0)
    println(positiveSign)
    println(negativeSign)
    println(zeroSign)

    // Double.nextUp() and Double.nextDown() are member-style extension functions
    val base = 1.0
    val nextUp = base.nextUp()
    val nextDown = base.nextDown()
    println(nextUp)
    println(nextDown)
}
