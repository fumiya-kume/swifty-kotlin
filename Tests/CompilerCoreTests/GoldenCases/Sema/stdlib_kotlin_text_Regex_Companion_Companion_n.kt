package golden.sema

fun escapedPattern(): String = Regex.escape("a.b\\E")

fun escapedReplacement(): String = Regex.escapeReplacement("a\$b\\c")
