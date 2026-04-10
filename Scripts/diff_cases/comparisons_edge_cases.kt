fun main() {
    println(compareValues(1, 2))
    println(compareValues(2, 2))
    println(compareValues(3, 2))
    println(compareValues(null, 1))
    println(compareValues(1, null))

    val words = listOf("pear", "apple", "fig")
    println(words.sorted())
}
