package golden.diagnostics

@Deprecated("Use replacement", level = DeprecationLevel.ERROR)
fun oldError(): Int = 1

@Deprecated("Use replacement")
fun oldWarning(): Int = 2

fun caller(): Int = oldError() + oldWarning()
