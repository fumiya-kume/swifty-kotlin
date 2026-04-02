import kotlin.math.*
fun main() {
    // Pre-existing roundToInt / roundToLong (STDLIB-510~511)
    println(3.7.roundToInt())
    println(3.2.roundToInt())
    println((-2.5).roundToInt())
    println(3.7.roundToLong())
    println(1.0.ulp)
    println(1.0.nextUp())
    println(2.0.nextDown())
    val f: Float = 3.7f
    println(f.roundToInt())
    println(f.roundToLong())

    // IEEE 754 rounding via kotlin.math standard functions
    // ceil — round toward positive infinity
    println(ceil(2.1))          // 3.0
    println(ceil(-2.9))         // -2.0
    println(ceil(2.0))          // 2.0
    // floor — round toward negative infinity
    println(floor(2.9))         // 2.0
    println(floor(-2.1))        // -3.0
    println(floor(3.0))         // 3.0
    // round — round half to even (banker's rounding)
    println(round(2.5))         // 2.0
    println(round(3.5))         // 4.0
    println(round(2.3))         // 2.0
    println(round(-2.5))        // -2.0

    // Float overloads
    val g: Float = 2.5f
    println(ceil(g))            // 3.0
    println(floor(g))           // 2.0
    println(round(g))           // 2.0
    println(ceil(2.1f))         // 3.0
    println(floor(2.9f))        // 2.0
}
