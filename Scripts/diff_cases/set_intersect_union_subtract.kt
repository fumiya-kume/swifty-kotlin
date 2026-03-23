fun main() {
    val a = setOf(1, 2, 3, 4)
    val b = setOf(3, 4, 5, 6)
    val c = listOf(2, 4, 8)

    // Basic intersect/union/subtract between sets
    println(a.intersect(b))
    println(a.union(b))
    println(a.subtract(b))

    // Set with Iterable (list)
    println(a.intersect(c))
    println(a.union(c))
    println(a.subtract(c))

    // Empty set cases
    val empty = emptySet<Int>()
    println(empty.intersect(a))
    println(a.intersect(empty))
    println(empty.intersect(empty))

    // Empty union/subtract
    println(empty.union(a))
    println(a.union(empty))
    println(a.subtract(a))

    // Intersect with itself
    println(a.intersect(a))

    // String sets
    val s1 = setOf("apple", "banana", "cherry")
    val s2 = setOf("banana", "date", "cherry")
    println(s1.intersect(s2))
    println(s1.union(s2))
    println(s1.subtract(s2))

    // Single element
    val single = setOf(3)
    println(a.intersect(single))
    println(single.intersect(a))

    // Intersect with list containing duplicates
    val dupes = listOf(2, 2, 3, 3, 4, 4)
    println(a.intersect(dupes))

    // Large disjoint sets
    val x = setOf(1, 2, 3)
    val y = setOf(4, 5, 6)
    println(x.intersect(y))

    // Chained operations
    println(a.intersect(b).union(setOf(10)))
    println(a.union(b).intersect(setOf(1, 6)))
    println(a.subtract(b).intersect(setOf(1, 5)))

    // Result type is Set
    val result: Set<Int> = a.intersect(b)
    println(result.size)
    println(result.contains(3))
    println(result.contains(1))
}
