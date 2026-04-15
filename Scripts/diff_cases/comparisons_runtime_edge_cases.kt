fun main() {
    val words = listOf("pear", "apple", "fig")
    val byLength = compareBy<String> { it.length }

    println(words.maxWithOrNull(byLength))
    println(words.minWithOrNull(byLength))

    val empty = emptyList<String>()
    println(empty.maxWithOrNull(byLength))
    println(empty.minWithOrNull(byLength))
}
