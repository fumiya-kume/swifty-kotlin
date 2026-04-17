package golden.diagnostics

// STDLIB-EXPERIMENTAL-001: @OptIn(...) at the call-site suppresses the opt-in diagnostic.

@RequiresOptIn(level = RequiresOptIn.Level.ERROR)
annotation class ExperimentalCallSiteMarker

@ExperimentalCallSiteMarker
fun callSiteApi(): Boolean = true

// @OptIn at function level — no diagnostic expected
@OptIn(ExperimentalCallSiteMarker::class)
fun useWithCallSiteOptIn(): Boolean = callSiteApi()

// Usage without opt-in — error diagnostic expected
fun useWithoutOptIn(): Boolean = callSiteApi()
