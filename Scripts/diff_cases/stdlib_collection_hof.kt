fun main() {
    println(listOf(1, 2, 3).filter { it > 1 }.map { it * 2 })

    val capture = 5
    println(listOf(1, 2, 3).map { it + capture })
    listOf(1, 2, 3).forEach { println(it + capture) }

    println(listOf(1, 2, 3).flatMap { listOf(it, it * 10) })
    println(listOf(1, 2, 3).fold(0) { acc, e -> acc + e })
    println(setOf(1, 2, 3).fold(0) { acc, e -> acc * 10 + e })
    println(listOf(1, 2, 3).reduce { acc, e -> acc + e })

    println(listOf(1, 2, 3, 4).any())
    println(listOf<Int>().none())
    println(listOf(1, 2, 3, 4).any { it > 2 })
    println(listOf(1, 2, 3, 4).all { it < 3 })
    println(listOf(1, 2, 3, 4).none { it == 2 })

    println(listOf(1, 2, 3, 4).count())
    println(listOf(1, 2, 3, 4).count { it % 2 == 0 })

    println(listOf(1, 2, 3).first())
    println(listOf(1, 2, 3).last())
    println(listOf(1, 2, 3).first { it > 1 })
    println(listOf(1, 2, 3).last { it < 3 })
    println(listOf(1, 2, 3).find { it == 2 })
    println(listOf(1, 2, 3).find { it == 9 })

    // groupBy: basic key selector
    val grouped = listOf(3, 1, 4, 2, 5).groupBy { it % 2 }
    println(grouped)
    println(grouped.get(1))

    // groupBy: empty list
    val emptyGrouped = listOf<Int>().groupBy { it % 2 }
    println(emptyGrouped)

    // groupBy: all same key
    val sameKey = listOf(2, 4, 6).groupBy { it % 2 }
    println(sameKey)

    // groupBy: with value transform (two-lambda variant)
    val groupedTransform = listOf(3, 1, 4, 2, 5).groupBy({ it % 2 }, { it * 10 })
    println(groupedTransform)

    // groupBy: with value transform on strings (two-lambda variant)
    val byLength = listOf("hi", "hey", "hello", "ok").groupBy({ it.length }, { it + "!" })
    println(byLength)

    // groupBy: single element list
    val single = listOf(42).groupBy { it % 2 }
    println(single)

    // groupBy: negative keys
    val negKeys = listOf(-3, -1, 0, 1, 3).groupBy { if (it < 0) -1 else if (it == 0) 0 else 1 }
    println(negKeys)

    // groupBy: result map get with existing key
    val g2 = listOf(1, 2, 3).groupBy { it % 2 }
    println(g2.get(0))
    println(g2.get(1))

    // groupBy: result map size
    val g3 = listOf(1, 2, 3, 4, 5, 6).groupBy { it % 3 }
    println(g3.size)

    // groupBy: value transform producing strings
    val g4 = listOf(1, 2, 3, 4).groupBy({ it % 2 }, { "n=$it" })
    println(g4)

    println(listOf(21, 11, 12, 22).sortedBy { it / 10 })
}
