// SKIP-DIFF: maxByOrNull/minByOrNull Comparable bound check on List pending
fun main() {
    val words = listOf("a", "bbb", "cc")
    println(words.maxByOrNull { value: String -> value })
    println(words.minByOrNull { value: String -> value })
    println(words.maxOfOrNull { value: String -> value.length })
    println(words.minOfOrNull { value: String -> value.length })

    val emptyWords = emptyList<String>()
    println(emptyWords.maxByOrNull { value: String -> value })
    println(emptyWords.minByOrNull { value: String -> value })
    println(emptyWords.maxOfOrNull { value: String -> value.length })
    println(emptyWords.minOfOrNull { value: String -> value.length })
}
