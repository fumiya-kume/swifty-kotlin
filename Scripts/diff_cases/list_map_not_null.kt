fun main() {
    val values = listOf(1, 0, 2)
    val numbers = values.mapNotNull { it }
    println(numbers)

    val nullable = listOf("a", null, "b", null)
    println(nullable.filterNotNull())
}
