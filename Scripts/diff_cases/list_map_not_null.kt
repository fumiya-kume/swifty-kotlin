fun main() {
    // Basic mapNotNull: identity on non-null list
    val values = listOf(1, 0, 2)
    val numbers = values.mapNotNull { it }
    println(numbers)

    // filterNotNull on list with nulls
    val nullable = listOf("a", null, "b", null)
    println(nullable.filterNotNull())

    // mapNotNull with transformation returning null for some elements
    val mixed = listOf(1, 2, 3, 4, 5)
    val evens = mixed.mapNotNull { if (it % 2 == 0) it * 10 else null }
    println(evens)

    // mapNotNull on empty list
    val empty = emptyList<Int>()
    println(empty.mapNotNull { it })

    // mapNotNull with all nulls returned
    val allNull = listOf(1, 2, 3).mapNotNull<Int, String> { null }
    println(allNull)

    // mapNotNull with string transformation
    val strings = listOf("hello", "", "world", "")
    val nonEmpty = strings.mapNotNull { if (it.isEmpty()) null else it.uppercase() }
    println(nonEmpty)

    // mapNotNull with nullable input list
    val withNulls = listOf<Int?>(1, null, 2, null, 3)
    val doubled = withNulls.mapNotNull { if (it != null) it * 2 else null }
    println(doubled)

    // mapNotNull result type and size
    val result = listOf(10, 20, 30).mapNotNull { if (it > 15) it else null }
    println(result.size)
    println(result)
}
