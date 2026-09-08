package golden.sema

fun elementAt(source: CharSequence, index: Int): Char = source.elementAt(index)

fun elementAtOrElse(source: CharSequence, index: Int): Char =
    source.elementAtOrElse(index) { requested -> if (requested < 0) '-' else '+' }

fun elementAtOrNull(source: CharSequence, index: Int): Char? = source.elementAtOrNull(index)

fun nonLocalDefault(source: CharSequence): Char {
    return source.elementAtOrElse(-1) { return 'x' }
}

fun namedDefault(source: CharSequence, value: Char): Char {
    source.elementAtOrElse(defaultValue = { return value }, index = -1)
    return '?'
}

fun namedSafeDefault(source: CharSequence?, value: Char): Char {
    source?.elementAtOrElse(defaultValue = { return value }, index = -1)
    return '?'
}
