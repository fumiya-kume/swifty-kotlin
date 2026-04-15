// SKIP-DIFF
import kotlin.math.*

fun main() {
    // Test rounding functions
    val values = listOf(3.2, 3.7, -2.3, -2.8, 0.5, -0.5)
    
    for (value in values) {
        println("Testing value: $value")
        
        // round() - nearest integer
        val rounded = round(value)
        println(rounded)
        
        // roundToInt() - nearest integer as Int
        val roundedInt = roundToInt(value)
        println(roundedInt)
        
        // roundToLong() - nearest integer as Long
        val roundedLong = roundToLong(value)
        println(roundedLong)
        
        // floor() - round down
        val floored = floor(value)
        println(floored)
        
        // ceil() - round up
        val ceiled = ceil(value)
        println(ceiled)
        
        // truncate() - truncate toward zero
        val truncated = truncate(value)
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
    
    // nextUp and nextDown
    val base = 1.0
    val nextUp = nextUp(base)
    val nextDown = nextDown(base)
    println(nextUp)
    println(nextDown)
}
