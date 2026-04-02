package golden.diagnostics

@Deprecated("Use replacement", replaceWith = ReplaceWith("newError()"), level = DeprecationLevel.ERROR)
fun oldError(): Int = 1

@Deprecated("Use replacement", replaceWith = ReplaceWith(expression = "newWarning()"))
fun oldWarning(): Int = 2

fun newError(): Int = 3
fun newWarning(): Int = 4

fun caller(): Int = oldError() + oldWarning() + newError() + newWarning()
