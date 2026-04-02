package golden.diagnostics

@RequiresOptIn(level = RequiresOptIn.Level.WARNING)
annotation class ExperimentalWarningApi

@ExperimentalWarningApi
fun unstableWarning(): Int = 1

fun callerWarning(): Int = unstableWarning()
