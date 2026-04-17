package golden.diagnostics

// STDLIB-EXPERIMENTAL-001: @RequiresOptIn with level=ERROR produces an error diagnostic
// when the API is used without explicit opt-in.

@RequiresOptIn(level = RequiresOptIn.Level.ERROR)
annotation class ExperimentalMarkerError

@ExperimentalMarkerError
fun errorLevelApi(): Int = 42

// Usage without opt-in — expects an error diagnostic
fun useWithoutOptIn(): Int = errorLevelApi()
