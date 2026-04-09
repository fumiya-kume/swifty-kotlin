fun main() {
    val words = listOf("pear", "apple", "fig")
    val byLength = compareBy<String> { it.length }

    println(words.maxWithOrNull(byLength))
    println(words.minWithOrNull(byLength))

    val empty = emptyList<String>()
    println(empty.maxWithOrNull(byLength))
    println(empty.minWithOrNull(byLength))

    try {
        println(empty.maxWith(byLength))
    } catch (e: Throwable) {
        println("maxWith-empty")
    }

    try {
        println(empty.minWith(byLength))
    } catch (e: Throwable) {
        println("minWith-empty")
    }
}
