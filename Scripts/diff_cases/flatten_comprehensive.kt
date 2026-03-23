fun main() {
    // Basic nested list flatten using flatMap
    val nested = listOf(listOf(1, 2, 3), listOf(4, 5), listOf(6))
    println(nested.flatMap { it })

    // Single inner list
    val single = listOf(listOf(10, 20, 30))
    println(single.flatMap { it })

    // Mixed sizes
    val mixed = listOf(listOf(1), listOf(2, 3, 4, 5), listOf(6, 7))
    println(mixed.flatMap { it })

    // Strings
    val strings = listOf(listOf("hello", "world"), listOf("foo"), listOf("bar", "baz"))
    println(strings.flatMap { it })

    // Large number of inner lists
    val many = listOf(listOf(1), listOf(2), listOf(3), listOf(4), listOf(5), listOf(6), listOf(7), listOf(8), listOf(9), listOf(10))
    println(many.flatMap { it })
}
