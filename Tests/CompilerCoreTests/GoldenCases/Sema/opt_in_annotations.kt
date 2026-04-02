package golden.sema

@RequiresOptIn(level = RequiresOptIn.Level.ERROR)
annotation class ExperimentalSemaApi

@ExperimentalSemaApi
fun unstableSema(): Int = 1

@OptIn(ExperimentalSemaApi::class)
fun callerSema(): Int = unstableSema()
