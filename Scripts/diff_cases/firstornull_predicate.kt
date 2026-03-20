fun main() {
    val numbers = listOf(1, 2, 3, 4, 5)
    val empty = emptyList<Int>()
    val strings = listOf("apple", "banana", "cherry")

    // firstOrNull() without predicate
    println(numbers.firstOrNull())
    println(empty.firstOrNull())

    // firstOrNull with predicate - matching
    println(numbers.firstOrNull { it > 3 })
    println(numbers.firstOrNull { it % 2 == 0 })

    // firstOrNull with predicate - no match
    println(numbers.firstOrNull { it > 100 })
    println(empty.firstOrNull { it > 0 })

    // firstOrNull on strings
    println(strings.firstOrNull { it.startsWith("b") })
    println(strings.firstOrNull { it.startsWith("z") })

    // firstOrNull with nullable elements
    val withNulls = listOf(null, 1, 2, null, 3)
    println(withNulls.firstOrNull())
    println(withNulls.firstOrNull { it != null })
    println(withNulls.firstOrNull { it == null })

    // firstOrNull on single-element list
    val single = listOf(42)
    println(single.firstOrNull())
    println(single.firstOrNull { it == 42 })
    println(single.firstOrNull { it == 99 })

    // firstOrNull result used in expression
    val result = numbers.firstOrNull { it > 2 } ?: -1
    println(result)
    val noResult = numbers.firstOrNull { it > 100 } ?: -1
    println(noResult)
}
