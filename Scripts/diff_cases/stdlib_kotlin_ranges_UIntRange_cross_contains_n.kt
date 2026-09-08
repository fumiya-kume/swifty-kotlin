fun main() {
    val ordinary = 4u..8u
    println(ordinary.contains(4.toUByte()))
    println(9.toUByte() in ordinary)
    println(ordinary.contains(8.toUShort()))
    println(3.toUShort() in ordinary)
    println(ordinary.contains(4uL))
    println(9uL in ordinary)

    val full = 0u..UInt.MAX_VALUE
    println(full.contains(UByte.MIN_VALUE))
    println(UByte.MAX_VALUE in full)
    println(full.contains(UShort.MAX_VALUE))
    println(UShort.MAX_VALUE in full)
    println(full.contains(UInt.MAX_VALUE.toULong()))
    println(UInt.MAX_VALUE.toULong() in full)
    println(full.contains(4294967296uL))
    println(4294967296uL in full)

    val empty = 5u..4u
    println(empty.contains(5.toUByte()))
    println(5uL in empty)
    println(empty.contains(5.toUShort()))
}
