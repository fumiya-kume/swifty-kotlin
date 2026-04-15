package golden.diagnostics

@RequiresOptIn(level = RequiresOptIn.Level.ERROR)
annotation class ExperimentalSuppressedApi

@ExperimentalSuppressedApi
fun unstableSuppressed(): Int = 1

@Suppress("OPT_IN_USAGE")
fun callerSuppressed(): Int = unstableSuppressed()
