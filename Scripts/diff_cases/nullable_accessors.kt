fun main() {
    val list = listOf(1, 2, 3)
    val empty = emptyList<Int>()

    // STDLIB-543: firstOrNull (no predicate)
    println(list.firstOrNull())
    println(empty.firstOrNull())

    // STDLIB-543: firstOrNull (predicate – match)
    println(list.firstOrNull { it > 1 })
    // STDLIB-543: firstOrNull (predicate – no match)
    println(list.firstOrNull { it > 10 })
    // STDLIB-543: firstOrNull (predicate – empty list)
    println(empty.firstOrNull { it > 0 })

    // STDLIB-544: lastOrNull (no predicate)
    println(list.lastOrNull())
    println(empty.lastOrNull())

    // STDLIB-544: lastOrNull (predicate – match)
    println(list.lastOrNull { it < 3 })
    // STDLIB-544: lastOrNull (predicate – no match)
    println(list.lastOrNull { it > 10 })
    // STDLIB-544: lastOrNull (predicate – empty list)
    println(empty.lastOrNull { it > 0 })

    // STDLIB-545: singleOrNull (no predicate – single element)
    println(listOf(42).singleOrNull())
    // STDLIB-545: singleOrNull (no predicate – empty list)
    println(empty.singleOrNull())
    // STDLIB-545: singleOrNull (no predicate – multi-element -> null)
    println(list.singleOrNull())

    // STDLIB-545: singleOrNull (predicate – unique match)
    println(list.singleOrNull { it == 2 })
    // STDLIB-545: singleOrNull (predicate – no match)
    println(list.singleOrNull { it > 10 })
    // STDLIB-545: singleOrNull (predicate – multiple matches -> null)
    println(list.singleOrNull { it > 1 })
    // STDLIB-545: singleOrNull (predicate – empty list)
    println(empty.singleOrNull { it > 0 })

    // STDLIB-545: getOrNull
    println(list.getOrNull(0))
    println(list.getOrNull(5))
    println(empty.getOrNull(0))
}
