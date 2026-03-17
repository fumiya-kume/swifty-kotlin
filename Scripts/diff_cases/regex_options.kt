fun main() {
    val multiline = Regex("^hello", RegexOption.MULTILINE)
    println(multiline.containsMatchIn("world\nhello"))
    val ignoreCase = Regex("hello", RegexOption.IGNORE_CASE)
    println(ignoreCase.matches("HELLO"))
    println(ignoreCase.matches("Hello"))
    val dotAll = Regex("a.b", RegexOption.DOT_MATCHES_ALL)
    println(dotAll.matches("a\nb"))
}
