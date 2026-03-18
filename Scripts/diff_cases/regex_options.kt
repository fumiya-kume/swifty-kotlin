fun main() {
    // STDLIB-597: MULTILINE — baseline without option (false), then with option (true)
    val multilineOff = Regex("^hello")
    println(multilineOff.containsMatchIn("world\nhello"))
    val multiline = Regex("^hello", RegexOption.MULTILINE)
    println(multiline.containsMatchIn("world\nhello"))

    // STDLIB-598: IGNORE_CASE — baseline without option (false), then with option (true)
    println("HELLO".matches(Regex("hello")))
    val ignoreCase = Regex("hello", RegexOption.IGNORE_CASE)
    println("HELLO".matches(ignoreCase))
    println("Hello".matches(ignoreCase))

    // STDLIB-599: DOT_MATCHES_ALL — baseline without option (false), then with option (true)
    println("a\nb".matches(Regex("a.b")))
    val dotAll = Regex("a.b", RegexOption.DOT_MATCHES_ALL)
    println("a\nb".matches(dotAll))
}
