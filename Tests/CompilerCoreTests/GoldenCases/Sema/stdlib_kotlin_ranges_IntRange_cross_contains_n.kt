package golden.sema

fun intRangeContainsByte(range: IntRange, value: Byte): Boolean =
    range.contains(value)

fun intRangeContainsLong(range: IntRange, value: Long): Boolean =
    range.contains(value)

fun intRangeContainsShort(range: IntRange, value: Short): Boolean =
    range.contains(value)

fun intRangeContainsByteIn(range: IntRange, value: Byte): Boolean =
    value in range

fun intRangeContainsLongIn(range: IntRange, value: Long): Boolean =
    value in range

fun intRangeContainsShortIn(range: IntRange, value: Short): Boolean =
    value in range

fun intRangeContainsInt(range: IntRange, value: Int): Boolean =
    range.contains(value)

fun intRangeContainsIntIn(range: IntRange, value: Int): Boolean =
    value in range

fun intRangeContainsByteNamed(range: IntRange, value: Byte): Boolean =
    range.contains(value = value)

fun intRangeContainsByteWrongLabel(range: IntRange, value: Byte): Boolean =
    range.contains(other = value)

fun intRangeContainsNullableByte(range: IntRange, value: Byte?): Boolean =
    range.contains(value)
