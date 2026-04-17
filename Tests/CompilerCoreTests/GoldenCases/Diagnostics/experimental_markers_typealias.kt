package golden.diagnostics

// STDLIB-EXPERIMENTAL-001: Opt-in markers can annotate typealias declarations;
// using the typealias at a call site requires opt-in.

@RequiresOptIn(level = RequiresOptIn.Level.ERROR)
annotation class ExperimentalTypeAliasMarker

@ExperimentalTypeAliasMarker
typealias ExperimentalAlias = String

// Usage of the typealias without opt-in — error diagnostic expected
val aliasedValue: ExperimentalAlias = "hello"
