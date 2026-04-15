import kotlin.math.*

fun main() {
    // Test exponential and logarithmic functions
    val x = 2.0
    
    // exp(1) = e ≈ 2.7183
    val expValue = exp(1.0)
    println(expValue)
    
    // exp(2) = e² ≈ 7.3891
    val exp2Value = exp(x)
    println(exp2Value)
    
    // log(e) = 1
    val logEValue = log(E)
    println(logEValue)
    
    // log(e²) = 2
    val logExp2Value = log(exp2Value)
    println(logExp2Value)
    
    // log2(8) = 3
    val log2Value = log2(8.0)
    println(log2Value)
    
    // log10(100) = 2
    val log10Value = log10(100.0)
    println(log10Value)
    
    // sqrt(16) = 4
    val sqrtValue = sqrt(16.0)
    println(sqrtValue)
    
    // sqrt(2) ≈ 1.4142
    val sqrt2Value = sqrt(2.0)
    println(sqrt2Value)
    
    // Test power function
    // pow(2, 3) = 8
    val powValue = pow(2.0, 3.0)
    println(powValue)
    
    // pow(10, 2) = 100
    val pow10Value = pow(10.0, 2.0)
    println(pow10Value)
}
