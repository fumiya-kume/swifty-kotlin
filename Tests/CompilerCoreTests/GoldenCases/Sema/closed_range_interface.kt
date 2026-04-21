package golden.sema

fun intClosedRangeValue(): ClosedRange<Int> = 1..10
fun longClosedRangeValue(): ClosedRange<Long> = 1L..10L
fun uintClosedRangeValue(): ClosedRange<UInt> = 1u..10u
fun ulongClosedRangeValue(): ClosedRange<ULong> = 1UL..10UL
fun charClosedRangeValue(): ClosedRange<Char> = 'a'..'z'

fun intClosedRangeContains(range: ClosedRange<Int>, value: Int): Boolean = value in range
fun longClosedRangeContains(range: ClosedRange<Long>, value: Long): Boolean = range.contains(value)
fun longClosedRangeIsEmpty(range: ClosedRange<Long>): Boolean = range.isEmpty()
fun uintClosedRangeContains(range: ClosedRange<UInt>, value: UInt): Boolean = value in range
fun ulongClosedRangeStart(range: ClosedRange<ULong>): ULong = range.start
fun charClosedRangeEnd(range: ClosedRange<Char>): Char = range.endInclusive
