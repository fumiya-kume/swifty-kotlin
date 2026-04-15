package golden.diagnostics

@RequiresOptIn(level = RequiresOptIn.Level.ERROR)
annotation class ExperimentalDeclaredApi

@ExperimentalDeclaredApi
fun unstableDeclared(): Int = 1

@OptIn(ExperimentalDeclaredApi::class)
fun callerDeclared(): Int = unstableDeclared()
