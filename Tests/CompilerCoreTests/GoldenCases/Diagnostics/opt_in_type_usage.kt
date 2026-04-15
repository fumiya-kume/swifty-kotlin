package golden.diagnostics

@RequiresOptIn(level = RequiresOptIn.Level.ERROR)
annotation class ExperimentalTypeApi

@ExperimentalTypeApi
class ExperimentalType

val typedValue: ExperimentalType = ExperimentalType()
