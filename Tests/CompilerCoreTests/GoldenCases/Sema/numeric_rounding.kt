import kotlin.math.roundToInt
import kotlin.math.roundToLong

fun main() {
    // Double rounding
    val d: Double = 3.7
    val dToInt: Int = d.roundToInt()
    val dToLong: Long = d.roundToLong()
    println(dToInt)
    println(dToLong)

    // Float rounding
    val f: Float = 2.3f
    val fToInt: Int = f.roundToInt()
    val fToLong: Long = f.roundToLong()
    println(fToInt)
    println(fToLong)
}
