// Kotlin `Int` is a 32-bit signed integer; arithmetic wraps around using
// two's complement. Verified against kotlinc.
fun addOne(x: Int): Int = x + 1
fun square(x: Int): Int = x * x
fun negate(x: Int): Int = -x
fun divide(a: Int, b: Int): Int = a / b
fun remainder(a: Int, b: Int): Int = a % b

fun main() {
    // Constant-folded overflow
    println(Int.MAX_VALUE + 1)
    println(Int.MIN_VALUE - 1)
    println(Int.MAX_VALUE * 2)
    println(100000 * 100000)
    println(-Int.MIN_VALUE)
    println(Int.MIN_VALUE / -1)
    println(Int.MIN_VALUE % -1)

    // Runtime-value overflow (not constant folded)
    println(addOne(Int.MAX_VALUE))
    println(square(100000))
    println(negate(Int.MIN_VALUE))
    println(divide(Int.MIN_VALUE, -1))
    println(remainder(Int.MIN_VALUE, -1))

    // Accumulating overflow in a loop
    var acc = 1
    for (i in 0 until 31) {
        acc *= 2
    }
    println(acc)

    // Long arithmetic must stay 64-bit
    println(2147483647L + 1L)
    println(1000000000L * 1000000000L)
    val i = 2000000000
    val l = 3000000000L
    println(i + l)
}
