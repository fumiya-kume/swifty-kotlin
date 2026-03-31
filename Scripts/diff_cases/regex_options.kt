fun main() {
    // STDLIB-REGEX-096: Regex options complete implementation

    // --- IGNORE_CASE ---
    val ci = Regex("[a-z]+", RegexOption.IGNORE_CASE)
    println(ci.containsMatchIn("HELLO"))
    println(ci.find("ABC123")?.value)
    println(ci.matches("Hello"))

    // --- MULTILINE ---
    val ml = Regex("^line", RegexOption.MULTILINE)
    println(ml.containsMatchIn("first\nline two"))
    val mlAll = ml.findAll("line1\nline2\nline3")
    println(mlAll.toList().size)

    // --- DOT_MATCHES_ALL ---
    val dot = Regex("a.b", RegexOption.DOT_MATCHES_ALL)
    println(dot.containsMatchIn("a\nb"))
    println(dot.containsMatchIn("axb"))

    // --- LITERAL ---
    val lit = Regex("[a-z]+", RegexOption.LITERAL)
    println(lit.containsMatchIn("hello"))
    println(lit.containsMatchIn("[a-z]+"))

    // --- UNIX_LINES ---
    val unix = Regex(".", RegexOption.UNIX_LINES)
    println(unix.containsMatchIn("a"))

    // --- COMMENTS ---
    val cmnt = Regex("a b  # match ab", RegexOption.COMMENTS)
    println(cmnt.containsMatchIn("ab"))

    // --- Multiple options with setOf ---
    val multi = Regex("[a-z]+", setOf(RegexOption.IGNORE_CASE, RegexOption.MULTILINE))
    println(multi.containsMatchIn("HELLO"))
    println(multi.find("ABC")?.value)
}
