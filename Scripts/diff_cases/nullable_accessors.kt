fun main() {
    val list = listOf(1, 2, 3)
    val empty = emptyList<Int>()

    // STDLIB-543: firstOrNull (no predicate)
    println("firstOrNull(list)=${list.firstOrNull()}")
    println("firstOrNull(empty)=${empty.firstOrNull()}")

    // STDLIB-544: lastOrNull (no predicate)
    println("lastOrNull(list)=${list.lastOrNull()}")
    println("lastOrNull(empty)=${empty.lastOrNull()}")

    // getOrNull (index-based nullable access)
    println("getOrNull(0)=${list.getOrNull(0)}")
    println("getOrNull(5)=${list.getOrNull(5)}")
    println("getOrNull(empty)=${empty.getOrNull(0)}")
}
