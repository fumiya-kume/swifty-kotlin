package golden.diagnostics

@RequiresOptIn(level = RequiresOptIn.Level.ERROR)
annotation class ExperimentalClassApi

@ExperimentalClassApi
fun unstableForClass(): Int = 1

@OptIn(ExperimentalClassApi::class)
class ClassLevelOptIn {
    fun caller(): Int = unstableForClass()
}
