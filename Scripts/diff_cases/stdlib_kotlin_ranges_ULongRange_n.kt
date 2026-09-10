// KSP-1292: a typed UInt value can select a user extension for a direct call,
// while a suffixed literal selects the actual ULong member and `in` keeps the
// stdlib widening behavior.
fun ULongRange.contains(value: UInt): Boolean = false

fun main() {
    val fullRange = 0UL..ULong.MAX_VALUE
    println(fullRange.contains(value = UByte.MAX_VALUE))
    println(UByte.MAX_VALUE in fullRange)
    println(fullRange.contains(value = UInt.MAX_VALUE))
    println(UInt.MAX_VALUE in fullRange)
    println(fullRange.contains(value = UShort.MAX_VALUE))
    println(UShort.MAX_VALUE in fullRange)
    println(fullRange.contains(value = 5UL))

    val literalRange = 0UL..10UL
    val explicitUInt: UInt = 5u
    val explicitULong: ULong = 5UL
    println("literal-direct=" + literalRange.contains(value = 5u))
    println("literal-in=" + (5u in literalRange))
    println("var-direct=" + literalRange.contains(value = explicitUInt))
    println("var-in=" + (explicitUInt in literalRange))
    println("ulong-direct=" + literalRange.contains(value = explicitULong))
    println("ulong-in=" + (explicitULong in literalRange))

    val narrowRange = 0UL..255UL
    println(narrowRange.contains(value = UByte.MAX_VALUE))
    println(narrowRange.contains(value = UInt.MAX_VALUE))
    println(narrowRange.contains(value = UShort.MAX_VALUE))

    val emptyRange = 10UL..5UL
    println(emptyRange.contains(value = UByte.MAX_VALUE))
    println(UInt.MAX_VALUE in emptyRange)
    println(emptyRange.contains(value = UShort.MAX_VALUE))
}
