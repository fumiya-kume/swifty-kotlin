package golden.diagnostics

@RequiresOptIn(level = RequiresOptIn.Level.ERROR)
annotation class ExperimentalDeprecatedApi

@ExperimentalDeprecatedApi
@Deprecated("Use stableReplacement", replaceWith = ReplaceWith("stableReplacement()"))
fun experimentalAndDeprecated(): Int = 1

fun stableReplacement(): Int = 2

// Caller opts in to the experimental marker but still gets a deprecation warning
@OptIn(ExperimentalDeprecatedApi::class)
fun callerWithOptIn(): Int = experimentalAndDeprecated()

// Caller has neither opt-in nor deprecation suppression
fun callerWithoutOptIn(): Int = experimentalAndDeprecated()
