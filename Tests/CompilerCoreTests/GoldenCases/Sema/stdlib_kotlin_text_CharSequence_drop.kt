package golden.sema

fun charSequenceDrop(source: CharSequence, n: Int): CharSequence =
    source.drop(n = n)

fun charSequenceDropLast(source: CharSequence, n: Int): CharSequence =
    source.dropLast(n)

fun charSequenceDropLastWhile(source: CharSequence, threshold: Char): CharSequence =
    source.dropLastWhile { it > threshold }

fun charSequenceDropWhile(source: CharSequence, threshold: Char): CharSequence =
    source.dropWhile { it < threshold }

fun stringDrop(source: String, n: Int): String =
    source.drop(n)

fun stringDropLast(source: String, n: Int): String =
    source.dropLast(n)

fun stringDropWhile(source: String, threshold: Char): String =
    source.dropWhile { it < threshold }
