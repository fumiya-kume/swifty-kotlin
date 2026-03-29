import kotlin.math.*
fun main() {
    // Pre-existing roundToInt / roundToLong (STDLIB-510~511)
    println(3.7.roundToInt())
    println(3.2.roundToInt())
    println((-2.5).roundToInt())
    println(3.7.roundToLong())
    println(1.0.ulp)
    println(0.0.nextUp)
    println(1.0.nextDown)
    val f: Float = 3.7f
    println(f.roundToInt())
    println(f.roundToLong())

    // STDLIB-111: IEEE 754 rounding modes — Double
    println(roundUp(2.3))       // 3.0
    println(roundUp(-2.3))      // -3.0
    println(roundDown(2.9))     // 2.0
    println(roundDown(-2.9))    // -2.0
    println(roundCeiling(2.1))  // 3.0
    println(roundCeiling(-2.9)) // -2.0
    println(roundFloor(2.9))    // 2.0
    println(roundFloor(-2.1))   // -3.0
    println(roundHalfUp(2.5))   // 3.0
    println(roundHalfUp(-2.5))  // -3.0
    println(roundHalfDown(2.5)) // 2.0
    println(roundHalfDown(-2.5))// -2.0
    println(roundHalfEven(2.5)) // 2.0 (banker's rounding)
    println(roundHalfEven(3.5)) // 4.0
    println(roundUnnecessary(3.0)) // 3.0

    // STDLIB-111: IEEE 754 rounding modes — Float
    val g: Float = 2.5f
    println(roundUp(g))         // 3.0
    println(roundDown(g))       // 2.0
    println(roundCeiling(g))    // 3.0
    println(roundFloor(g))      // 2.0
    println(roundHalfUp(g))     // 3.0
    println(roundHalfDown(g))   // 2.0
    println(roundHalfEven(g))   // 2.0
    println(roundUnnecessary(2.0f)) // 2.0
}
