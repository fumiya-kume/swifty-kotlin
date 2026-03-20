import kotlin.math.roundToInt
import kotlin.math.roundToLong

fun main() {
    // Double rounding
    val d1: Double = 3.7
    val d2: Double = 3.2
    println(d1.roundToInt())
    println(d2.roundToInt())
    println(d1.roundToLong())
    println(d2.roundToLong())

    // Float rounding
    val f1: Float = 2.7f
    val f2: Float = 2.2f
    println(f1.roundToInt())
    println(f2.roundToInt())
    println(f1.roundToLong())
    println(f2.roundToLong())
}
