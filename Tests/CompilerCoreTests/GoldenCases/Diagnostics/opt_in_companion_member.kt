package golden.diagnostics

@RequiresOptIn(level = RequiresOptIn.Level.ERROR)
annotation class ExperimentalCompanionApi

class HostClass {
    companion object {
        @ExperimentalCompanionApi
        fun experimentalCompanionFun(): Int = 99
    }
}

@OptIn(ExperimentalCompanionApi::class)
fun callerWithOptIn(): Int = HostClass.experimentalCompanionFun()

fun callerWithoutOptIn(): Int = HostClass.experimentalCompanionFun()
