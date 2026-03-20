fun main() {
    // Basic union of two sets
    val a = setOf(1, 2, 3)
    val b = setOf(3, 4, 5)
    println(a.union(b))

    // Union with empty set
    val empty = emptySet<Int>()
    println(a.union(empty))
    println(empty.union(a))

    // Union with itself (idempotent)
    println(a.union(a))

    // Union with a list (Iterable parameter)
    val list = listOf(2, 3, 6, 7)
    println(a.union(list))

    // Union preserves order (receiver elements first, then new from other)
    val x = setOf(5, 3, 1)
    val y = setOf(4, 2, 6)
    println(x.union(y))

    // Union with duplicates in list argument
    val dupes = listOf(1, 1, 2, 2, 3, 3, 8)
    println(a.union(dupes))

    // String sets
    val s1 = setOf("hello", "world")
    val s2 = setOf("world", "kotlin")
    println(s1.union(s2))

    // Union result size
    println(a.union(b).size)

    // Chained unions
    val c = setOf(10, 20)
    println(a.union(b).union(c))

    // Union with single-element set
    println(a.union(setOf(99)))

    // Large overlap (all elements shared)
    val same1 = setOf(1, 2, 3)
    val same2 = setOf(1, 2, 3)
    println(same1.union(same2))

    // MutableSet union (produces Set)
    val m = mutableSetOf(10, 20, 30)
    val n = setOf(20, 40)
    println(m.union(n))

    // Union with empty list
    println(a.union(emptyList()))

    // Boolean set union
    val boolA = setOf(true, false)
    val boolB = setOf(true)
    println(boolA.union(boolB))
}
