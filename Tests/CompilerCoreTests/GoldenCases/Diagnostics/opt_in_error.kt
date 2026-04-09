package golden.diagnostics

@RequiresOptIn(level = RequiresOptIn.Level.ERROR)
annotation class ExperimentalErrorApi

@ExperimentalErrorApi
fun unstableError(): Int = 1

fun callerError(): Int = unstableError()
