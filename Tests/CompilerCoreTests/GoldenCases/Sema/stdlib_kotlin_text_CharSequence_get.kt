package golden.sema

fun getOrElse(source: CharSequence, index: Int): Char =
    source.getOrElse(index) { requested -> if (requested < 0) '-' else '+' }

fun getOrNull(source: CharSequence, index: Int): Char? = source.getOrNull(index)

fun namedReturn(source: CharSequence, value: Char): Char {
    source.getOrElse(defaultValue = { return value }, index = -1)
    return '?'
}

fun safeReturn(source: CharSequence?, value: Char): Char {
    source?.getOrElse(defaultValue = { return value }, index = -1)
    return '?'
}
