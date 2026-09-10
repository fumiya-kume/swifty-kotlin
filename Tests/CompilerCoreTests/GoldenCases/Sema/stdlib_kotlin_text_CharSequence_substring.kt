package golden.sema

fun charSequenceSubstringDefault(source: CharSequence): String =
    source.substring(1)

fun charSequenceSubstringBounded(source: CharSequence): String =
    source.substring(startIndex = 1, endIndex = 3)

fun charSequenceSubstringRange(source: CharSequence): String =
    source.substring(1..3)

fun charSequenceSubstringNamedRange(source: CharSequence): String =
    source.substring(range = 1..3)

fun stringSubstringRange(source: String): String =
    source.substring(1..3)
