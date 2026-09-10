package golden.sema

fun charSequenceMatches(value: CharSequence, regex: Regex): Boolean =
    value.matches(regex)

fun charSequenceMatchesInfix(value: CharSequence, regex: Regex): Boolean =
    value matches regex

fun charSequenceMatchesNamed(value: CharSequence): Boolean =
    value.matches(regex = Regex("^alpha$"))

fun stringMatches(value: String, regex: Regex): Boolean =
    value.matches(regex)

fun stringBuilderMatches(value: StringBuilder, regex: Regex): Boolean =
    value matches regex
