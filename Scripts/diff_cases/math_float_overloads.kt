import kotlin.math.*

fun main() {
    val f: Float = 1.0f

    // Trig functions — Float in, Float out
    val sinF: Float = sin(f)
    val cosF: Float = cos(f)
    val tanF: Float = tan(f)
    println(sinF)
    println(cosF)
    println(tanF)

    val asinF: Float = asin(0.5f)
    val acosF: Float = acos(0.5f)
    val atanF: Float = atan(0.5f)
    println(asinF)
    println(acosF)
    println(atanF)

    val atan2F: Float = atan2(1.0f, 2.0f)
    println(atan2F)

    // sqrt, round, ceil, floor — Float in, Float out
    val sqrtF: Float = sqrt(4.0f)
    println(sqrtF)

    val roundF: Float = round(2.5f)
    println(roundF)

    val ceilF: Float = ceil(2.3f)
    println(ceilF)

    val floorF: Float = floor(2.7f)
    println(floorF)

    // abs — Float in, Float out
    val absF: Float = abs(-3.14f)
    println(absF)

    // exp, ln, log2, log10 — Float in, Float out
    val expF: Float = exp(1.0f)
    println(expF)

    val lnF: Float = ln(2.0f)
    println(lnF)

    val log2F: Float = log2(8.0f)
    println(log2F)

    val log10F: Float = log10(100.0f)
    println(log10F)

    // log(x, base) — Float in, Float out
    val logF: Float = log(8.0f, 2.0f)
    println(logF)

    // sign — Float in, Float out
    val signF: Float = sign(-5.0f)
    println(signF)

    val signPosF: Float = sign(5.0f)
    println(signPosF)

    val signZeroF: Float = sign(0.0f)
    println(signZeroF)

    // hypot — Float in, Float out
    val hypotF: Float = hypot(3.0f, 4.0f)
    println(hypotF)
}
