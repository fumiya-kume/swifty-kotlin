package golden.diagnostics

@RequiresOptIn(level = RequiresOptIn.Level.ERROR)
annotation class ExperimentalPropertyApi

@ExperimentalPropertyApi
fun unstableForProperty(): Int = 42

val experimentalGetter: Int
    @OptIn(ExperimentalPropertyApi::class)
    get() = unstableForProperty()

val missingOptInGetter: Int
    get() = unstableForProperty()
