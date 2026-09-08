package golden.sema

fun ulongRangeCrossContains(
    range: ULongRange,
    byteValue: UByte,
    uintValue: UInt,
    shortValue: UShort,
): Boolean {
    val directUByte = range.contains(value = byteValue)
    val directUInt = range.contains(value = uintValue)
    val directUShort = range.contains(value = shortValue)
    val ordinaryULong = range.contains(value = 5UL)
    val inOperator = byteValue in range
    val emptyRange = 10UL..5UL
    val emptyCross = uintValue in emptyRange
    val fullRange = 0UL..ULong.MAX_VALUE
    val unsignedBoundaries =
        UByte.MAX_VALUE in fullRange &&
            UInt.MAX_VALUE in fullRange &&
            UShort.MAX_VALUE in fullRange
    return directUByte && directUInt && directUShort && ordinaryULong &&
        inOperator && !emptyCross && unsignedBoundaries
}
