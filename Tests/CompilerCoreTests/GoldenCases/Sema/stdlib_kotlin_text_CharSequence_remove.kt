package golden.sema

fun removeRangeIndices(source: CharSequence): CharSequence = source.removeRange(1, 3)

fun removeRangeIntRange(source: CharSequence): CharSequence = source.removeRange(1..2)

fun removeRangeStringAsCharSequence(): CharSequence {
    val source: CharSequence = "A😀BC"
    return source.removeRange(1, 3)
}

fun removeRangeStringBuilderAsCharSequence(): CharSequence {
    val source: CharSequence = StringBuilder("A😀BC")
    return source.removeRange(1..2)
}

fun removeRangeEmpty(source: CharSequence): CharSequence = source.removeRange(2, 2)
