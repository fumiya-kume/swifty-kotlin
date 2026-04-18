package golden.diagnostics

@RequiresOptIn(level = RequiresOptIn.Level.ERROR)
annotation class ExperimentalPropagatedApi

@ExperimentalPropagatedApi
fun unstablePropagated(): Int = 1

// Propagate marker: caller itself is marked, so callers of it also need opt-in
@ExperimentalPropagatedApi
fun propagatedCaller(): Int = unstablePropagated()

// This caller opts-in to only the original marker, which also covers propagatedCaller
@OptIn(ExperimentalPropagatedApi::class)
fun safeTopLevelCaller(): Int = propagatedCaller()

fun unsafeTopLevelCaller(): Int = propagatedCaller()
