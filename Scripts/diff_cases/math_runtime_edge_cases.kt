import kotlin.math.*

fun main() {
    println(2.0.pow(10.0))
    println(log2(1024.0))
    println(ln(E))

    println(sqrt(Double.POSITIVE_INFINITY).isInfinite())
    println(sqrt(Double.NaN).isNaN())

    println(ln(Double.POSITIVE_INFINITY).isInfinite())
    println(ln(Double.NaN).isNaN())

    println((-1.0).pow(3.0))
    println((-1.0).pow(2.0))
}
