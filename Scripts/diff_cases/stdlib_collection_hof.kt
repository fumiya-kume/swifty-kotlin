fun main() {
    println(listOf(1, 2, 3).filter { it > 1 }.map { it * 2 })

    val capture = 5
    println(listOf(1, 2, 3).map { it + capture })
    listOf(1, 2, 3).forEach { println(it + capture) }

    println(listOf(1, 2, 3).flatMap { listOf(it, it * 10) })
    println(listOf(1, 2, 3).fold(0) { acc, e -> acc + e })
    println(listOf(1, 2, 3).reduce { acc, e -> acc + e })

    println(listOf(1, 2, 3, 4).any())
    println(listOf<Int>().none())
    println(listOf(1, 2, 3, 4).any { println("any"); it > 2 })
    println(listOf(1, 2, 3, 4).all { println("all"); it < 3 })
    println(listOf(1, 2, 3, 4).none { println("none"); it == 2 })

    println(listOf(1, 2, 3, 4).count())
    println(listOf(1, 2, 3, 4).count { it % 2 == 0 })

    println(listOf(1, 2, 3).first())
    println(listOf(1, 2, 3).last())
    println(listOf(1, 2, 3).first { it > 1 })
    println(listOf(1, 2, 3).last { it < 3 })
    println(listOf(1, 2, 3).find { it == 2 })
    println(listOf(1, 2, 3).find { it == 9 })

    val grouped = listOf(3, 1, 4, 2, 5).groupBy { it % 2 }
    println(grouped)
    println(grouped.get(1))

    println(listOf(21, 11, 12, 22).sortedBy { it / 10 })
}
