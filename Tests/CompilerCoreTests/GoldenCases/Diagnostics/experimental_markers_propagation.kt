package golden.diagnostics

// STDLIB-EXPERIMENTAL-001: Propagation marker — an intermediate function annotated
// with the opt-in marker itself propagates the requirement to its callers.

@RequiresOptIn(level = RequiresOptIn.Level.ERROR)
annotation class ExperimentalPropagationMarker

@ExperimentalPropagationMarker
fun coreApi(): Int = 1

// Propagation: this function is itself marked, so its callers also need opt-in
@ExperimentalPropagationMarker
fun propagatingWrapper(): Int = coreApi()

// Caller without opt-in — expects error on propagatingWrapper call
fun useWithoutOptIn(): Int = propagatingWrapper()
