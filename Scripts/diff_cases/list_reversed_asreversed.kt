fun main() {
    // Basic reversed() returns a new list (copy)
    val list = listOf(1, 2, 3, 4, 5)
    val rev = list.reversed()
    println(rev)
    println(rev is List<*>)

    // Basic asReversed() returns a reversed view
    val asRev = list.asReversed()
    println(asRev)
    println(asRev is List<*>)

    // reversed() on mutable list returns independent copy
    val mutable = mutableListOf(10, 20, 30)
    val mutableRev = mutable.reversed()
    mutable[0] = 99
    println(mutableRev)  // should still be [30, 20, 10]

    // asReversed() on mutable list reflects changes
    val mutable2 = mutableListOf(10, 20, 30)
    val view = mutable2.asReversed()
    println(view)         // [30, 20, 10]
    mutable2[0] = 99
    println(view)         // [30, 20, 99]
    mutable2.add(40)
    println(view)         // [40, 30, 20, 99]

    // Empty list
    println(emptyList<Int>().reversed())
    println(emptyList<Int>().asReversed())

    // Single element
    println(listOf(42).reversed())
    println(listOf(42).asReversed())

    // String list
    println(listOf("a", "b", "c").reversed())
    println(listOf("a", "b", "c").asReversed())

    // Double reversed
    println(listOf(1, 2, 3).reversed().reversed())
    println(listOf(1, 2, 3).asReversed().asReversed())

    // Size and indexing on reversed view
    val view2 = listOf(5, 10, 15).asReversed()
    println(view2.size)
    println(view2[0])
    println(view2[2])
}
