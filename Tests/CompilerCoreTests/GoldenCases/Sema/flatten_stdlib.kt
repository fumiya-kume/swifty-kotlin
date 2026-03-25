fun main() {
    // Basic flatten functionality
    println(listOf(listOf(1, 2), listOf(3, 4)).flatten())
    
    // Empty cases
    println(emptyList<List<Int>>().flatten())
    println(listOf(listOf<Int>()).flatten())
    println(listOf(listOf<Int>(), listOf<Int>()).flatten())
    
    // Mixed empty and non-empty
    println(listOf(listOf<Int>(), listOf(1), listOf<Int>()).flatten())
    
    // Single element cases
    println(listOf(listOf(42)).flatten())
    
    // String collections
    println(listOf(listOf("a", "b"), listOf("c")).flatten())
    println(listOf(listOf<String>(), listOf("x")).flatten())
    
    // Large data (sample)
    val large = (1..10).map { listOf(it) }
    println(large.flatten().size)
    println(large.flatten().take(3))
}
