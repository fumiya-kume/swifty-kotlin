fun main() {
    // Basic nested list flatten
    val nested = listOf(listOf(1, 2, 3), listOf(4, 5), listOf(6))
    println(nested.flatten())

    // Empty inner lists
    val withEmpty = listOf(listOf<Int>(), listOf(1, 2), listOf<Int>(), listOf(3))
    println(withEmpty.flatten())

    // All empty inner lists
    val allEmpty = listOf(listOf<Int>(), listOf<Int>(), listOf<Int>())
    println(allEmpty.flatten())

    // Single inner list
    val single = listOf(listOf(10, 20, 30))
    println(single.flatten())

    // Empty outer list
    val emptyOuter = listOf<List<Int>>()
    println(emptyOuter.flatten())

    // Mixed sizes
    val mixed = listOf(listOf(1), listOf(2, 3, 4, 5), listOf(6, 7))
    println(mixed.flatten())

    // Strings
    val strings = listOf(listOf("hello", "world"), listOf("foo"), listOf<String>(), listOf("bar", "baz"))
    println(strings.flatten())

    // Nullable element type
    val nullable = listOf(listOf<Int?>(1, null, 2), listOf<Int?>(null), listOf<Int?>(3))
    println(nullable.flatten())

    // Large number of inner lists
    val many = listOf(listOf(1), listOf(2), listOf(3), listOf(4), listOf(5), listOf(6), listOf(7), listOf(8), listOf(9), listOf(10))
    println(many.flatten())

    // Boolean lists
    val bools = listOf(listOf(true, false), listOf(false, true, true))
    println(bools.flatten())
}
