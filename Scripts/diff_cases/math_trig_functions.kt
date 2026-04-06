import kotlin.math.*

fun main() {
    // Test trigonometric functions
    val angle = PI / 4.0  // 45 degrees
    
    // sin(π/4) = √2/2 ≈ 0.7071
    val sinValue = sin(angle)
    println(sinValue)
    
    // cos(π/4) = √2/2 ≈ 0.7071
    val cosValue = cos(angle)
    println(cosValue)
    
    // tan(π/4) = 1
    val tanValue = tan(angle)
    println(tanValue)
    
    // asin(√2/2) = π/4
    val asinValue = asin(sinValue)
    println(asinValue)
    
    // acos(√2/2) = π/4
    val acosValue = acos(cosValue)
    println(acosValue)
    
    // atan(1) = π/4
    val atanValue = atan(1.0)
    println(atanValue)
    
    // atan2(1, 1) = π/4
    val atan2Value = atan2(1.0, 1.0)
    println(atan2Value)
    
    // Test hyperbolic functions
    val x = 1.0
    
    // sinh(1) ≈ 1.1752
    val sinhValue = sinh(x)
    println(sinhValue)
    
    // cosh(1) ≈ 1.5431
    val coshValue = cosh(x)
    println(coshValue)
    
    // tanh(1) ≈ 0.7616
    val tanhValue = tanh(x)
    println(tanhValue)
}
