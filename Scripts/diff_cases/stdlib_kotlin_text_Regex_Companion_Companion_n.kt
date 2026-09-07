fun main() {
    val literal = "a.b\\E[c]"
    val pattern = Regex.escape(literal)
    println(pattern)
    println(Regex(pattern).matches(literal))
    println(Regex(pattern).matches("axb\\E[c]"))
    println(Regex.escapeReplacement("a\$b\\c"))
    println(Regex.escapeReplacement("plain"))
}
