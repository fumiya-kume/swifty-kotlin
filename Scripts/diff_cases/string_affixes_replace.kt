// Execution coverage for the string APIs checked by the RF-FIXTURE-022 Sema
// fixtures but not covered by stdlib_string_ops.kt / string_edge_cases.kt /
// string_indent.kt: affix removal, substringAfter family, blankness checks,
// first / firstOrNull on strings, equals / equalsIgnoreCase, and the
// replaceFirst / replaceRange family.
fun main() {
    println("hello".removePrefix("he"))
    println("hello".removeSuffix("lo"))
    println("[hello]".removeSurrounding("[", "]"))
    println("**foo**".removeSurrounding("*"))
    println("hello.world.kt".substringAfter("."))
    println("hello.world.kt".substringAfterLast("."))

    println("".isEmpty())
    println("x".isNotEmpty())
    println("  ".isBlank())
    println("x".isNotBlank())

    println("hello".first())
    println("".firstOrNull())

    println("abc".equals("abc"))
    println("abc".equals("ABC", ignoreCase = true))

    println("abcabc".replaceFirst("abc", "X"))
    println("abcABC".replaceFirst("abc", "X", ignoreCase = true))
    println("hello".replaceRange(0..2, "HE"))
}
