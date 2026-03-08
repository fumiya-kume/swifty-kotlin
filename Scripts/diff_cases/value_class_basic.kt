@JvmInline
value class Meter(val value: Int)

fun main() {
    val m = Meter(42)
    println(m.value)
}
