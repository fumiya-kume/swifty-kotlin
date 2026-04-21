package golden.sema

// STDLIB-TEXT-EDGE-001: split with ignoreCase and limit

fun useSplitIgnoreCase(): List<String> = "aXbXc".split("x", ignoreCase = true)

fun useSplitIgnoreCaseLimit(): List<String> = "aXbXcXd".split("x", ignoreCase = true, limit = 2)

fun useSplitLimit(): List<String> = "a,b,c,d".split(",", ignoreCase = false, limit = 3)
