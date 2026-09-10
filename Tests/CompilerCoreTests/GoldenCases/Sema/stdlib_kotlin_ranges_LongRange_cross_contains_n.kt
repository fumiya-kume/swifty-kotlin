package golden.sema

fun longRangeContainsByte(range: LongRange, value: Byte): Boolean =
    range.contains(value)

fun longRangeContainsInt(range: LongRange, value: Int): Boolean =
    range.contains(value)

fun longRangeContainsShort(range: LongRange, value: Short): Boolean =
    range.contains(value)

fun longRangeInByte(range: LongRange, value: Byte): Boolean =
    value in range

fun longRangeInInt(range: LongRange, value: Int): Boolean =
    value in range

fun longRangeInShort(range: LongRange, value: Short): Boolean =
    value in range
