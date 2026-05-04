fun show(match: Pair<Int, String>?) {
    if (match == null) println("null") else println(match.first.toString() + ":" + match.second)
}

fun main() {
    val text: CharSequence = "Kotlin"
    show(text.findLastAnyOf(listOf("ot", "li"), 5, false))
    show(text.findLastAnyOf(listOf("KO"), 5, true))
    show("abc".findLastAnyOf(listOf("x", "bc"), 2, false))
    show("abc".findLastAnyOf(listOf(""), 5, false))
    show("abc".findLastAnyOf(listOf(""), 2, false))
    show("abc".findLastAnyOf(listOf("a"), -1, false))
    show("abc".findLastAnyOf(listOf("C"), 2, true))
    show("abc".findLastAnyOf(listOf("bc", "b"), 2, false))
    show("abc".findLastAnyOf(listOf("a"), 5, false))
}
