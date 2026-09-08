package golden.sema

fun charSequenceRepeat(source: CharSequence, count: Int): String = source.repeat(count)

fun charSequenceRepeatBuilder(source: StringBuilder): String = source.repeat(2)

fun charSequenceRepeatEmpty(source: CharSequence): String = source.repeat(0)

fun stringRepeat(): String = "x".repeat(2)
