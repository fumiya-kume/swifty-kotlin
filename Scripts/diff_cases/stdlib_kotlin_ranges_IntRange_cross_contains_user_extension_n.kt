// KSP-1285: a user extension with the same signature must win over the
// bundled IntRange.contains(Byte) overload in direct and `in` calls.
operator fun IntRange.contains(value: Byte): Boolean = false

fun typed(range: IntRange, value: Byte): Boolean = range.contains(value)

fun main() {
    val range = 0..10
    println(typed(range, 5.toByte()))
    println(range.contains(5.toByte()))
    println(5.toByte() in range)
}
