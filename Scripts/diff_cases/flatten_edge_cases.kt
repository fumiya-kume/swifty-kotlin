fun main() {
    // Empty nested lists
    println("=== Empty nested lists ===")
    println(emptyList<List<Int>>().flatten())  // []
    println(listOf(listOf<Int>()).flatten())  // []
    println(listOf(listOf<Int>(), listOf<Int>()).flatten())  // []
    println(listOf(listOf<Int>(), listOf(1), listOf<Int>()).flatten())  // [1]
    
    // Deep nesting (flatten only works one level)
    println("\n=== Deep nesting ===")
    val deep = listOf(listOf(listOf(1, 2), listOf(3)), listOf(listOf(4)))
    println(deep.flatten())  // Should only flatten one level
    
    // Mixed types with Any
    println("\n=== Mixed types ===")
    val mixed: List<List<Any>> = listOf(listOf(1, "a"), listOf(2.5, true))
    println(mixed.flatten())
    
    // Large data
    println("\n=== Large data ===")
    val large = (1..100).map { listOf(it) }
    val flattened = large.flatten()
    println(flattened.size)
    println(flattened.take(5))
    println(flattened.drop(flattened.size - 5))
    
    // Single element edge cases
    println("\n=== Single element cases ===")
    println(listOf(listOf<Int>()).flatten())  // []
    println(listOf(listOf(42)).flatten())    // [42]
    
    // Nested empty collections
    println("\n=== Nested empty collections ===")
    println(listOf(listOf<Int>(), listOf<Int>(), listOf<Int>()).flatten())  // []
    println(listOf(listOf(1), listOf<Int>(), listOf(2)).flatten())        // [1, 2]
}
