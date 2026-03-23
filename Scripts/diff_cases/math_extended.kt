import kotlin.math.*

fun main() {
    // abs(Long)
    val absLong: Long = abs(-42L)
    println(absLong)
    val absLongZero: Long = abs(0L)
    println(absLongZero)

    // truncate(Double)
    val truncD: Double = truncate(3.7)
    println(truncD)
    val truncDNeg: Double = truncate(-3.7)
    println(truncDNeg)

    // truncate(Float)
    val truncF: Float = truncate(3.7f)
    println(truncF)
    val truncFNeg: Float = truncate(-3.7f)
    println(truncFNeg)

    // IEEErem(Double, Double)
    val remD: Double = IEEErem(7.0, 2.5)
    println(remD)

    // IEEErem(Float, Float)
    val remF: Float = IEEErem(7.0f, 2.5f)
    println(remF)

    // Double.withSign(Double)
    val ws1: Double = withSign(3.0, -1.0)
    println(ws1)
    val ws2: Double = withSign(-3.0, 1.0)
    println(ws2)

    // Float.withSign(Float)
    val wsF: Float = withSign(3.0f, -1.0f)
    println(wsF)

    // Double.withSign(Int)
    val wsI: Double = withSign(3.0, -1)
    println(wsI)

    // nextTowards(Double, Double)
    val nt: Double = nextTowards(1.0, 2.0)
    println(nt)
}
