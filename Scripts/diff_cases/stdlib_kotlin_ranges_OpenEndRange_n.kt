fun openEndRangeByteContainsInt(range: OpenEndRange<Byte>, value: Int): Boolean =
    range.contains(value)

fun openEndRangeByteContainsLong(range: OpenEndRange<Byte>, value: Long): Boolean =
    range.contains(value)

fun openEndRangeByteContainsShort(range: OpenEndRange<Byte>, value: Short): Boolean =
    range.contains(value)

fun openEndRangeDoubleContainsFloat(range: OpenEndRange<Double>, value: Float): Boolean =
    range.contains(value)

fun openEndRangeIntContainsByte(range: OpenEndRange<Int>, value: Byte): Boolean =
    range.contains(value)

fun openEndRangeIntContainsLong(range: OpenEndRange<Int>, value: Long): Boolean =
    range.contains(value)

fun openEndRangeIntContainsShort(range: OpenEndRange<Int>, value: Short): Boolean =
    range.contains(value)

fun openEndRangeLongContainsByte(range: OpenEndRange<Long>, value: Byte): Boolean =
    range.contains(value)

fun openEndRangeLongContainsInt(range: OpenEndRange<Long>, value: Int): Boolean =
    range.contains(value)

fun openEndRangeLongContainsShort(range: OpenEndRange<Long>, value: Short): Boolean =
    range.contains(value)

fun openEndRangeShortContainsByte(range: OpenEndRange<Short>, value: Byte): Boolean =
    range.contains(value)

fun openEndRangeShortContainsInt(range: OpenEndRange<Short>, value: Int): Boolean =
    range.contains(value)

fun openEndRangeShortContainsLong(range: OpenEndRange<Short>, value: Long): Boolean =
    range.contains(value)

fun intRangeCrossTypeContains(range: OpenEndRange<Int>): Boolean =
    range.contains(4.toByte()) &&
        range.contains(4L) &&
        range.contains(4.toShort()) &&
        !range.contains(2147483648L)

fun longRangeCrossTypeContains(range: OpenEndRange<Long>): Boolean =
    range.contains(4.toByte()) &&
        range.contains(4) &&
        range.contains(4.toShort())

fun main() {
    val intRange: OpenEndRange<Int> = 1..<5
    val longRange: OpenEndRange<Long> = 1L..<5L
    println(intRangeCrossTypeContains(intRange))
    println(longRangeCrossTypeContains(longRange))
    // Exercise the representation-preserving Byte -> Short lowering used by
    // the OpenEndRange<Short>.contains(Byte) implementation.
    println(4.toByte().toShort())
}
