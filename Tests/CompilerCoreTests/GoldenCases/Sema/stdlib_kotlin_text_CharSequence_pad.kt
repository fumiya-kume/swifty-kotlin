package golden.sema

fun charSequencePadStart(source: CharSequence, length: Int, padChar: Char): CharSequence =
    source.padStart(length, padChar)

fun charSequencePadStartDefault(source: CharSequence, length: Int): CharSequence =
    source.padStart(length)

fun charSequencePadEnd(source: CharSequence, length: Int, padChar: Char): CharSequence =
    source.padEnd(length, padChar)

fun charSequencePadEndDefault(source: CharSequence, length: Int): CharSequence =
    source.padEnd(length)

fun stringPadStart(source: String, length: Int, padChar: Char): String =
    source.padStart(length, padChar)

fun stringPadEnd(source: String, length: Int, padChar: Char): String =
    source.padEnd(length, padChar)
