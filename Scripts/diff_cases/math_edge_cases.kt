import kotlin.math.*

fun main() {
    println(sqrt(16.0))
    println(sqrt(-1.0).isNaN())

    println(abs(-42))
    println(abs(Double.NEGATIVE_INFINITY).isInfinite())

    println(round(2.5))
    println(round(-2.5))

    println(ceil(2.1))
    println(floor(-2.1))

    println(ceil(Double.NaN).isNaN())
    println(floor(Double.POSITIVE_INFINITY).isInfinite())
}
