fun main() {
    // Basic reversed() returns a new list
    val list = listOf(1, 2, 3, 4, 5)
    val rev = list.reversed()
    println(rev)

    // Basic asReversed() returns a reversed view
    val asRev = list.asReversed()
    println(asRev)

    // reversed() on mutable list returns independent copy
    val mutable = mutableListOf(10, 20, 30)
    val mutableRev = mutable.reversed()
    mutable[0] = 99
    println(mutableRev)

    // asReversed() on mutable list reflects changes
    val mutable2 = mutableListOf(10, 20, 30)
    val view = mutable2.asReversed()
    println(view)
    mutable2[0] = 99
    println(view)
    mutable2.add(40)
    println(view)

    // Single element
    println(listOf(42).reversed())
    println(listOf(42).asReversed())

    // String list
    println(listOf("a", "b", "c").reversed())
    println(listOf("a", "b", "c").asReversed())

    // Double reversed
    println(listOf(1, 2, 3).reversed().reversed())

    // Size and indexing on reversed view
    val view2 = listOf(5, 10, 15).asReversed()
    println(view2.size)
    println(view2[0])
    println(view2[2])
}
