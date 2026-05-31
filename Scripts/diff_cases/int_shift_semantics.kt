// Kotlin shift operators: `Int` uses only the low 5 bits of the shift
// distance and produces 32-bit results; `Long` uses the low 6 bits.
// Verified against kotlinc.
fun shl(x: Int, n: Int): Int = x shl n
fun shr(x: Int, n: Int): Int = x shr n
fun ushr(x: Int, n: Int): Int = x ushr n

fun main() {
    // Int shl: shift distance masked to 5 bits
    println(1 shl 31)
    println(1 shl 32)
    println(1 shl 33)
    println(shl(1, 32))
    println(shl(1, 33))

    // Int shr (arithmetic) and ushr (logical)
    println(-8 shr 1)
    println(256 shr 4)
    println(-1 ushr 28)
    println(-1 ushr 0)
    println(ushr(-1, 28))
    println(Int.MIN_VALUE shr 31)
    println(Int.MIN_VALUE ushr 31)
    println(shr(-256, 4))

    // Int bitwise
    println(0xFF and 0x0F)
    println(0xF0 or 0x0F)
    println(0b1010 xor 0b0110)
    println(0.inv())
    println(255.inv())

    // Long shifts use the low 6 bits and stay 64-bit
    println(1L shl 40)
    println(1L shl 64)
    println(-1L ushr 60)
    println(1024L shr 2)
}
