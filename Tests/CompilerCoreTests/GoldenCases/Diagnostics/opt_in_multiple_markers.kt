package golden.diagnostics

@RequiresOptIn(level = RequiresOptIn.Level.ERROR)
annotation class ExperimentalAlphaApi

@RequiresOptIn(level = RequiresOptIn.Level.WARNING)
annotation class ExperimentalBetaApi

@ExperimentalAlphaApi
fun unstableAlpha(): Int = 1

@ExperimentalBetaApi
fun unstableBeta(): Int = 2

@OptIn(ExperimentalAlphaApi::class, ExperimentalBetaApi::class)
fun callerBothOptedIn(): Int = unstableAlpha() + unstableBeta()

fun callerMissingBoth(): Int = unstableAlpha() + unstableBeta()
