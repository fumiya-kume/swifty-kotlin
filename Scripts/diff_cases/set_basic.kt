fun main() {
    val set = setOf(1, 2, 2, 3)
    println(set)
    println(set.size)
    println(set.contains(2))
    println(set.isEmpty())

    val mutable = mutableSetOf(1, 2)
    println(mutable.add(2))
    println(mutable.add(3))
    println(mutable.remove(1))
    println(mutable)
    println(emptySet<Int>().isEmpty())

    // Set operations
    println(setOf(1, 2, 3).union(setOf(3, 4, 5)))
    println(setOf(1, 2, 3).intersect(setOf(2, 3, 4)))
    println(setOf(1, 2, 3).subtract(setOf(2, 3)))

    // MutableSet: retainAll
    val s = mutableSetOf(1, 2, 3)
    s.retainAll(setOf(2, 3))
    println(s)

    // filter, filterNot
    println(setOf(1, 2, 3, 4, 5).filter { it > 2 })
    println(setOf(1, 2, 3, 4, 5).filterNot { it > 2 })

    // map, mapNotNull, flatMap
    println(setOf(1, 2, 3).map { it * 2 })
    println(setOf(1, 2, 3, 4).mapNotNull { if (it % 2 == 0) it * 10 else null })
    println(setOf(1, 2, 3).flatMap { listOf(it, it * 10) })
}
