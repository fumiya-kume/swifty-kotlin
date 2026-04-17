package golden.diagnostics

// STDLIB-EXPERIMENTAL-001: Opt-in marker on one overload but not the other —
// only the marked overload requires opt-in.

@RequiresOptIn(level = RequiresOptIn.Level.ERROR)
annotation class ExperimentalOverloadMarker

fun compute(x: Int): Int = x * 2

@ExperimentalOverloadMarker
fun compute(x: String): Int = x.length

// Stable overload — no diagnostic
val stableResult: Int = compute(21)

// Experimental overload without opt-in — error diagnostic expected
val experimentalResult: Int = compute("hello")
