fun main() {
    val ignoreCase = Regex("hello", RegexOption.IGNORE_CASE)
    println(ignoreCase.containsMatchIn("HeLLo"))

    val dotDefault = Regex("a.b")
    val dotAll = Regex("a.b", RegexOption.DOT_MATCHES_ALL)
    println(dotDefault.containsMatchIn("a\nb"))
    println(dotAll.containsMatchIn("a\nb"))

    val combined = Regex(
        "^hello.world$",
        setOf(RegexOption.IGNORE_CASE, RegexOption.DOT_MATCHES_ALL, RegexOption.MULTILINE)
    )
    println(combined.containsMatchIn("HELLO\nWORLD"))
    println(combined.matchEntire("hello\nworld")?.value)
}
