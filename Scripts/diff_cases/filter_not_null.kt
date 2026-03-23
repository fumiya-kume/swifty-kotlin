fun main() {
    // Basic filterNotNull on List<String?>
    val nullable = listOf("a", null, "b", null, "c")
    println(nullable.filterNotNull())

    // filterNotNull on List<Int?>
    val nums = listOf(1, null, 2, null, 3)
    println(nums.filterNotNull())

    // filterNotNull on list with no nulls
    val noNulls = listOf<String?>("x", "y", "z")
    println(noNulls.filterNotNull())

    // filterNotNull result
    val result = listOf("hello", null, "world").filterNotNull()
    println(result)
    println(result.size)

    // Chaining filterNotNull with other operations
    val chained = listOf(1, null, 2, null, 3).filterNotNull().map { it * 2 }
    println(chained)

    // filterNotNull preserves order
    val ordered = listOf<Int?>(5, null, 3, null, 1, null, 4, null, 2)
    println(ordered.filterNotNull())
}
