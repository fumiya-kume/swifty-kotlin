fun main() {
    // Basic subtract: Set - Set
    val a = setOf(1, 2, 3, 4, 5)
    val b = setOf(3, 4, 5, 6, 7)
    println(a.subtract(b))

    // subtract with List argument
    val c = listOf(2, 4)
    println(a.subtract(c))

    // subtract with empty set
    println(a.subtract(emptySet()))

    // subtract where all elements removed
    println(a.subtract(a))

    // subtract with no overlap
    val d = setOf(10, 20)
    println(a.subtract(d))

    // subtract with String sets
    val s1 = setOf("a", "b", "c", "d")
    val s2 = setOf("b", "d", "e")
    println(s1.subtract(s2))

    // subtract preserves receiver order
    val ordered = setOf(5, 4, 3, 2, 1)
    val rem = setOf(2, 4)
    println(ordered.subtract(rem))

    // subtract with duplicates in the Iterable argument
    val dupList = listOf(1, 1, 2, 2, 3)
    println(a.subtract(dupList))

    // subtract result type is Set (check size and contains)
    val result = a.subtract(b)
    println(result.size)
    println(result.contains(1))
    println(result.contains(3))

    // chained subtract
    println(a.subtract(setOf(1)).subtract(setOf(2)))
}
