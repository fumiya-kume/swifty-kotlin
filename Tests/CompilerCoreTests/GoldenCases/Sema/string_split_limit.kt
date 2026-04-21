package golden.sema

// STDLIB-TEXT-EDGE-001: split with limit / ignoreCase

fun useSplitLimitOnly(): List<String> = "a,b,c,d".split(",", limit = 2)

fun useSplitLimitOnlyThree(): List<String> = "a,b,c,d".split(",", limit = 3)

fun useSplitDefaultSplit(): List<String> = "a,b,c,d".split(",")

fun useSplitMultiCharLimit(): List<String> = "one::two::three".split("::", limit = 2)

fun useSplitIgnoreCase(): List<String> = "aXbXc".split("x", ignoreCase = true)

fun useSplitIgnoreCaseLimit(): List<String> = "aXbXcXd".split("x", ignoreCase = true, limit = 2)

fun useSplitLimit(): List<String> = "a,b,c,d".split(",", ignoreCase = false, limit = 3)
