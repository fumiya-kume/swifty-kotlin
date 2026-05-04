fun show(match: Pair<Int, String>?) {
    if (match == null) println("null") else println(match.first.toString() + ":" + match.second)
}

fun main() {
    val text: CharSequence = "Kotlin"
    show(text.findAnyOf(listOf("lin", "ot"), 0, false))
    show(text.findAnyOf(listOf("KO"), 0, true))
    show("abc".findAnyOf(listOf("x", "bc"), 0, false))
    show("abc".findAnyOf(listOf(""), 5, false))
    show("abc".findAnyOf(listOf("a"), 5, false))
    show("abc".findAnyOf(listOf("bc", "b"), 0, false))
    show("abc".findAnyOf(listOf("a"), -1, false))
}
