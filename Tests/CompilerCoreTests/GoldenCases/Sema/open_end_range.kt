// STDLIB-RANGE-IFACE-003: OpenEndRange interface surface

fun useOpenEndRange(range: OpenEndRange<Int>, value: Int): Boolean {
    return value in range && !range.isEmpty() && range.start < range.endExclusive
}
