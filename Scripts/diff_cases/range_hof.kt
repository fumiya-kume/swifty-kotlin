fun main() {
    println((1..5).toList())
    (1..3).forEach { print(it) }
    println()
    println((1..3).map { it * 2 })

    // Test new HOFs
    println("=== Transformation HOFs ===")
    println((1..5).mapIndexed { index, value -> index * value })
    println((1..5).mapNotNull { if (it % 2 == 0) it else null })

    println("=== Filtering HOFs ===")
    println((1..10).filter { it % 2 == 0 })
    println((1..10).filterIndexed { index, value -> index % 2 == 0 })
    println((1..10).filterNot { it % 2 == 0 })

    println("=== Aggregation HOFs ===")
    println((1..5).reduce { acc, value -> acc + value })
    println((1..5).reduceIndexed { index, acc, value -> acc + index * value })
    println((1..5).fold(10) { acc, value -> acc + value })
    println((1..5).foldIndexed(10) { index, acc, value -> acc + index * value })

    println("=== Search HOFs ===")
    println((1..10).find { it % 3 == 0 })
    println((1..10).findLast { it % 3 == 0 })
    println((1..10).first { it % 3 == 0 })
    println((1..10).firstOrNull { it > 10 })
    println((1..10).last { it % 3 == 0 })
    println((1..10).lastOrNull { it > 10 })

    println("=== Predicate HOFs ===")
    println((1..10).any { it % 2 == 0 })
    println((1..10).all { it <= 10 })
    println((1..10).none { it > 10 })

    println("=== Partitioning HOFs ===")
    println((1..10).chunked(3))
    println((1..10).windowed(3, 2, true))

    // Test edge cases
    println("=== Edge Cases ===")
    println((5..1).map { it * 2 }) // Empty range
    try {
        println((5..1).reduce { acc, value -> acc + value }) // Should throw
    } catch (e: Exception) {
        println("reduce on empty range threw: ${e.message}")
    }
    println((1..1).map { it * 3 }) // Single element
}
