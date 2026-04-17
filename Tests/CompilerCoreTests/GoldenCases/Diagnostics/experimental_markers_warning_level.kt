package golden.diagnostics

// STDLIB-EXPERIMENTAL-001: @RequiresOptIn with level=WARNING produces a warning diagnostic
// when the API is used without explicit opt-in.

@RequiresOptIn(level = RequiresOptIn.Level.WARNING)
annotation class ExperimentalMarkerWarning

@ExperimentalMarkerWarning
fun warningLevelApi(): String = "unstable"

// Usage without opt-in — expects a warning diagnostic
fun useWithoutOptIn(): String = warningLevelApi()
