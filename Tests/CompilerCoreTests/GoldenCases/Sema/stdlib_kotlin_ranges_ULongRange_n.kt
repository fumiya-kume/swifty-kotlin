package golden.sema

fun ULongRange.contains(value: UInt): Boolean = false

fun ulongRangeCrossContains(
    range: ULongRange,
    byteValue: UByte,
    uintValue: UInt,
    shortValue: UShort,
): Boolean {
    val literalRange = 0UL..10UL
    val explicitUInt: UInt = 5u
    val explicitULong: ULong = 5UL
    val literalDirect = literalRange.contains(value = 5u)
    val literalIn = 5u in literalRange
    val variableDirect = literalRange.contains(value = explicitUInt)
    val variableIn = explicitUInt in literalRange
    val directUByte = range.contains(value = byteValue)
    val directUInt = range.contains(value = uintValue)
    val directUShort = range.contains(value = shortValue)
    val ordinaryULong = range.contains(value = explicitULong)
    val inOperator = byteValue in range
    val emptyRange = 10UL..5UL
    val emptyCross = uintValue in emptyRange
    val fullRange = 0UL..ULong.MAX_VALUE
    val unsignedBoundaries =
        UByte.MAX_VALUE in fullRange &&
            UInt.MAX_VALUE in fullRange &&
            UShort.MAX_VALUE in fullRange
    return literalDirect && literalIn && !variableDirect && variableIn &&
        literalRange.contains(value = explicitULong) &&
        directUByte && !directUInt && directUShort && ordinaryULong &&
        inOperator && !emptyCross && unsignedBoundaries
}
