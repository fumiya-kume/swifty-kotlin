fun main() {
    // STDLIB-599: RegexOption.DOT_MATCHES_ALL
    // Without DOT_MATCHES_ALL, dot does not match newline
    val noFlag = Regex("a.b")
    println(noFlag.containsMatchIn("a\nb"))
    println(noFlag.containsMatchIn("axb"))

    // With DOT_MATCHES_ALL, dot matches newline
    val withFlag = Regex("a.b", RegexOption.DOT_MATCHES_ALL)
    println(withFlag.containsMatchIn("a\nb"))
    println(withFlag.containsMatchIn("axb"))

    // find with DOT_MATCHES_ALL
    val multi = Regex("start.+end", RegexOption.DOT_MATCHES_ALL)
    val found = multi.find("start\nmiddle\nend")
    println(found?.value)

    // matchEntire with DOT_MATCHES_ALL
    val full = Regex(".+", RegexOption.DOT_MATCHES_ALL)
    val m = full.matchEntire("line1\nline2")
    println(m?.value)

    // Combining with setOf
    val combined = Regex("hello.world", setOf(RegexOption.DOT_MATCHES_ALL, RegexOption.IGNORE_CASE))
    println(combined.containsMatchIn("HELLO\nWORLD"))
    println(combined.containsMatchIn("hello world"))
}
