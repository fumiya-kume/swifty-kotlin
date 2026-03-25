import kotlin.math.*

fun main() {
    // Edge cases for Float overloads
    
    // Special floating-point values
    val posInf: Float = Float.POSITIVE_INFINITY
    val negInf: Float = Float.NEGATIVE_INFINITY
    val nan: Float = Float.NaN
    
    // Test trig functions with special values
    println(sin(posInf)) // should be NaN
    println(sin(negInf)) // should be NaN
    println(sin(nan))     // should be NaN
    
    println(cos(posInf)) // should be NaN
    println(cos(negInf)) // should be NaN
    println(cos(nan))     // should be NaN
    
    // Test sqrt with negative and special values
    println(sqrt(-1.0f))  // should be NaN
    println(sqrt(posInf))  // should be Infinity
    println(sqrt(nan))    // should be NaN
    
    // Test abs with special values
    println(abs(posInf))  // should be Infinity
    println(abs(negInf))  // should be Infinity
    println(abs(nan))     // should be NaN
    
    // Test log with special values
    println(log(0.0f))    // should be -Infinity
    println(log(-1.0f))   // should be NaN
    println(log(posInf))   // should be Infinity
    println(log(nan))     // should be NaN
    
    // Test exp with special values
    println(exp(posInf))   // should be Infinity
    println(exp(negInf))   // should be 0.0
    println(exp(nan))     // should be NaN
    
    // Test round with special values
    println(round(posInf)) // should be Infinity
    println(round(negInf)) // should be -Infinity
    println(round(nan))    // should be NaN
    
    // Test ceil/floor with special values
    println(ceil(posInf))  // should be Infinity
    println(floor(negInf))  // should be -Infinity
    println(ceil(nan))     // should be NaN
    println(floor(nan))    // should be NaN
    
    // Test very small and large numbers
    val tiny: Float = 1.0e-10f
    val huge: Float = 1.0e10f
    
    println(sin(tiny))
    println(cos(huge))
    println(sqrt(tiny))
    println(log(huge))
    
    // Test precision edge cases
    val nearZero: Float = 1.0e-7f
    val nearOne: Float = 0.9999999f
    
    println(asin(nearZero))
    println(acos(nearOne))
    
    // Test atan2 with special combinations
    println(atan2(0.0f, 0.0f))    // should be 0.0
    println(atan2(posInf, negInf))  // should be 2.3561945 (3π/4)
    println(atan2(nan, 1.0f))      // should be NaN
    println(atan2(1.0f, nan))      // should be NaN
    
    // Test hypot with special values
    println(hypot(posInf, 0.0f))   // should be Infinity
    println(hypot(0.0f, negInf))   // should be Infinity
    println(hypot(nan, 1.0f))      // should be NaN
    println(hypot(3.0f, 4.0f))     // should be 5.0
    
    // Test sign function with special values
    println(sign(posInf))  // should be 1.0
    println(sign(negInf))  // should be -1.0
    println(sign(nan))     // should be NaN
    println(sign(0.0f))    // should be 0.0
    println(sign(-0.0f))   // should be -0.0
}
