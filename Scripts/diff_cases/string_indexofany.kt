fun main() {
    val text: CharSequence = "Kotlin"
    println(text.indexOfAny(charArrayOf('t', 'x'), 0, false))
    println(text.indexOfAny(charArrayOf('k'), 0, true))
    println("abc".indexOfAny(charArrayOf('x'), 0, false))
    println("abc".indexOfAny(charArrayOf('a'), 5, false))
    println("abc".indexOfAny(charArrayOf('B'), 0, true))
    println(text.indexOfAny(listOf("lin", "zz"), 0, false))
    println(text.indexOfAny(listOf("ko"), 0, true))
    println("abc".indexOfAny(listOf("x", "bc"), 0, false))
    println("abc".indexOfAny(listOf(""), 2, false))
    println("abc".indexOfAny(listOf("a"), 5, false))
}
