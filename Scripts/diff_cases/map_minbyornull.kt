fun main() {
    // Basic minByOrNull on Map<String, Int> by value
    val scores = mapOf("alice" to 90, "bob" to 70, "charlie" to 85)
    println(scores.minByOrNull { it.value })
    println(scores.minByOrNull { it.value }?.key)
    println(scores.minByOrNull { it.value }?.value)

    // minByOrNull by key (lexicographic)
    println(scores.minByOrNull { it.key })
    println(scores.minByOrNull { it.key }?.key)

    // Empty map returns null
    val empty = emptyMap<String, Int>()
    println(empty.minByOrNull { it.value })

    // Single-element map
    val single = mapOf("only" to 42)
    println(single.minByOrNull { it.value })

    // Negative values
    val negatives = mapOf("a" to -5, "b" to -10, "c" to 0)
    println(negatives.minByOrNull { it.value }?.key)
    println(negatives.minByOrNull { it.value }?.value)

    // minByOrNull with string length selector
    val words = mapOf(1 to "hello", 2 to "hi", 3 to "hey")
    println(words.minByOrNull { it.value.length }?.value)

    // Comparison with maxByOrNull on same map
    println(scores.maxByOrNull { it.value }?.key)
    println(scores.minByOrNull { it.value }?.key)

    // Map<Int, String> - minByOrNull by key
    val indexed = mapOf(3 to "c", 1 to "a", 2 to "b")
    println(indexed.minByOrNull { it.key }?.value)

    // Chained safe calls on nullable result
    val result: String? = empty.minByOrNull { it.value }?.key
    println(result)
    println(result ?: "default")
}
