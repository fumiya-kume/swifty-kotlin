package golden.sema

fun charSequenceTake(source: CharSequence, n: Int): CharSequence =
    source.take(n = n)

fun charSequenceTakeLast(source: CharSequence, n: Int): CharSequence =
    source.takeLast(n = n)

fun charSequenceTakeLastWhile(source: CharSequence, threshold: Char): CharSequence =
    source.takeLastWhile { it > threshold }

fun charSequenceTakeWhile(source: CharSequence, threshold: Char): CharSequence =
    source.takeWhile { it < threshold }

fun stringTake(source: String, n: Int): String =
    source.take(n)

fun stringTakeLast(source: String, n: Int): String =
    source.takeLast(n)

fun stringTakeWhile(source: String, threshold: Char): String =
    source.takeWhile { it < threshold }
