package golden.diagnostics

@RequiresOptIn(level = RequiresOptIn.Level.ERROR)
annotation class ExperimentalFuncApi

@ExperimentalFuncApi
fun unstableForFunc(): Int = 1

@OptIn(ExperimentalFuncApi::class)
fun callerWithFuncOptIn(): Int = unstableForFunc()

fun callerWithoutFuncOptIn(): Int = unstableForFunc()
