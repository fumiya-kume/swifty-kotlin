// KSP-815: The five Native-only code-point/radix constants are covered by the
// Sema golden because the JVM kotlinc reference does not declare them.
fun main() {
    println(Char.MAX_HIGH_SURROGATE.code)
    println(Char.MAX_LOW_SURROGATE.code)
    println(Char.MAX_SURROGATE.code)
    println(Char.MAX_VALUE.code)
    println(Char.MIN_HIGH_SURROGATE.code)
    println(Char.MIN_LOW_SURROGATE.code)
    println(Char.MIN_SURROGATE.code)
    println(Char.MIN_VALUE.code)
    println(Char.SIZE_BITS)
    println(Char.SIZE_BYTES)
}
