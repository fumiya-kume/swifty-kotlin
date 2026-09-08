fun main() {
    val fullRange = 0UL..ULong.MAX_VALUE
    println(fullRange.contains(value = UByte.MAX_VALUE))
    println(UByte.MAX_VALUE in fullRange)
    println(fullRange.contains(value = UInt.MAX_VALUE))
    println(UInt.MAX_VALUE in fullRange)
    println(fullRange.contains(value = UShort.MAX_VALUE))
    println(UShort.MAX_VALUE in fullRange)
    println(fullRange.contains(value = 5UL))

    val narrowRange = 0UL..255UL
    println(narrowRange.contains(value = UByte.MAX_VALUE))
    println(narrowRange.contains(value = UInt.MAX_VALUE))
    println(narrowRange.contains(value = UShort.MAX_VALUE))

    val emptyRange = 10UL..5UL
    println(emptyRange.contains(value = UByte.MAX_VALUE))
    println(UInt.MAX_VALUE in emptyRange)
    println(emptyRange.contains(value = UShort.MAX_VALUE))
}
