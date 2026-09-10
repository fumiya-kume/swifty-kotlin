package golden.sema

fun containsSequence(source: CharSequence, other: CharSequence): Boolean =
    source.contains(other)

fun containsSequenceNamed(source: CharSequence, other: CharSequence): Boolean =
    source.contains(other = other, ignoreCase = true)

fun containsSequenceOperator(source: CharSequence, other: CharSequence): Boolean =
    other in source

fun containsChar(source: CharSequence): Boolean =
    source.contains('x')

fun containsCharNamed(source: CharSequence): Boolean =
    source.contains(char = 'x', ignoreCase = true)

fun containsCharOperator(source: CharSequence): Boolean =
    'x' in source

fun containsRegex(source: CharSequence): Boolean =
    source.contains(Regex("x+"))

fun containsRegexNamed(source: CharSequence): Boolean =
    source.contains(regex = Regex("x+"))

fun containsRegexOperator(source: CharSequence): Boolean =
    Regex("x+") in source

fun containsStringRegex(): Boolean =
    "xxx".contains(Regex("x+"))

fun containsBuilder(): Boolean {
    val source: CharSequence = StringBuilder("Box")
    return source.contains('x', ignoreCase = true)
}
