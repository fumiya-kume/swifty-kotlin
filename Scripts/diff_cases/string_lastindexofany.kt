fun main() {
    val text: CharSequence = "Kotlin"
    println(text.lastIndexOfAny(charArrayOf('t', 'o'), 5, false))
    println(text.lastIndexOfAny(charArrayOf('k'), 5, true))
    println("abca".lastIndexOfAny(charArrayOf('a'), 2, false))
    println("abc".lastIndexOfAny(charArrayOf('x'), 2, false))
    println("abc".lastIndexOfAny(charArrayOf('C'), 2, true))
    println("abc".lastIndexOfAny(charArrayOf('a'), -1, false))
    println(text.lastIndexOfAny(listOf("ot", "li"), 5, false))
    println(text.lastIndexOfAny(listOf("KO"), 5, true))
    println("abc".lastIndexOfAny(listOf("x", "bc"), 2, false))
    println("abc".lastIndexOfAny(listOf(""), 5, false))
    println("abc".lastIndexOfAny(listOf(""), 2, false))
    println("abc".lastIndexOfAny(listOf("a"), -1, false))
}
