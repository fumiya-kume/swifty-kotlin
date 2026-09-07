// SKIP-DIFF (DEBT-DIFF-001): kotlin.native.BitSet is Kotlin/Native-only and has no JVM kotlinc counterpart.
@file:OptIn(kotlin.native.ObsoleteNativeApi::class)

import kotlin.native.BitSet

fun main() {
    val bits = BitSet(2)
    val other = BitSet(130)
    bits.set(1)
    bits.set(2, 5)
    bits.set(0..1, false)
    bits.set(10, 12, false)
    bits.flip(4)
    bits.flip(5, 7)
    bits.flip(8..9)
    println(bits.toString())
    println(bits.size)
    println(bits.lastTrueIndex)
    println(bits.nextSetBit())
    println(bits.nextClearBit())
    println(bits.previousSetBit(20))
    println(bits.previousClearBit(4))
    println(bits.previousBit(20, true))
    println(bits[4])
    println(bits.isEmpty)
    println(bits.hashCode() != 0)

    bits.clear(4)
    bits.clear(5, 7)
    bits.clear(8..9)
    bits.clear(0, 1)
    bits.clear()
    bits.and(other)
    bits.or(other)
    bits.xor(other)
    bits.andNot(other)
    println(bits.intersects(other))
    println(bits.equals(other))
}
