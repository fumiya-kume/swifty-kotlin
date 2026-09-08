package golden.sema

fun charSequenceLast(source: CharSequence): Char = source.last()

fun charSequenceLastPredicate(source: CharSequence): Char = source.last { it == 'x' }

fun charSequenceLastOrNull(source: CharSequence): Char? = source.lastOrNull()

fun charSequenceLastOrNullPredicate(source: CharSequence): Char? =
    source.lastOrNull { it == 'x' }

fun charSequenceLastIndex(source: CharSequence): Int = source.lastIndex

fun stringLast(): Char = "x".last()

fun stringLastOrNull(): Char? = "".lastOrNull()

fun stringBuilderLast(source: StringBuilder): Char = source.last()

fun stringBuilderLastOrNull(source: StringBuilder): Char? = source.lastOrNull()

fun stringBuilderLastIndex(source: StringBuilder): Int = source.lastIndex

fun capturedLast(source: CharSequence): Char {
    val expected = 'x'
    return source.last { it == expected }
}

fun nonLocalLast(source: CharSequence, value: Char): Char {
    source.last {
        if (it == 'x') return value
        false
    }
    return '?'
}
