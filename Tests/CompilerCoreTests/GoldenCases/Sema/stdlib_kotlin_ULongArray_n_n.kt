package golden.sema

@OptIn(ExperimentalUnsignedTypes::class)

fun makeULongArraySizeOnly(): ULongArray = ULongArray(3)

fun makeULongArrayFromLongView(source: LongArray): ULongArray = source.asULongArray()
