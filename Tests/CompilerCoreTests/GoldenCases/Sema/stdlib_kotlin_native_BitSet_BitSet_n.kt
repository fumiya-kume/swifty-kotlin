@file:OptIn(kotlin.native.ObsoleteNativeApi::class)

package golden.sema

import kotlin.native.BitSet

fun bitSetMembers(): Int {
    val bits = BitSet(2)
    val other = BitSet(130)

    bits.set(1)
    bits.set(2, 5)
    bits.set(0..1, false)
    bits.set(10, 12, false)
    bits.flip(4)
    bits.flip(5, 7)
    bits.flip(8..9)
    val indexed = bits[4]
    val nextSet = bits.nextSetBit()
    val nextSetFrom = bits.nextSetBit(5)
    val nextClear = bits.nextClearBit()
    val nextClearFrom = bits.nextClearBit(5)
    val previousSet = bits.previousSetBit(20)
    val previousClear = bits.previousClearBit(4)
    val previous = bits.previousBit(20, true)
    val last = bits.lastTrueIndex
    val empty = bits.isEmpty
    val size = bits.size
    val rendered = bits.toString()
    val hash = bits.hashCode()

    bits.clear(4)
    bits.clear(5, 7)
    bits.clear(8..9)
    bits.clear(0, 1)
    bits.clear()
    bits.and(other)
    bits.or(other)
    bits.xor(other)
    bits.andNot(other)
    val intersects = bits.intersects(other)
    val equal = bits.equals(other)

    return if (
        indexed &&
        nextSet == 4 &&
        nextSetFrom == 5 &&
        nextClear == 0 &&
        nextClearFrom == 5 &&
        previousSet == 9 &&
        previousClear == 4 &&
        previous == 9 &&
        last == 9 &&
        !empty &&
        size == 10 &&
        rendered == "[4|5|6|7|8|9]" &&
        hash != 0 &&
        !intersects &&
        !equal
    ) {
        1
    } else {
        0
    }
}
