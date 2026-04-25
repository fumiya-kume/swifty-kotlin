fun main() {
    val list = listOf(1, 2, 3, 4, 5)
    println(list.filter { it > 1 }.map { it * 2 })
    println(list.map { it * 2 })
    println(list.filter { it > 3 })
    list.forEach { println(it) }
    println(list.flatMap { listOf(it, it * 10) })
    println(list.any { it > 3 })
    println(list.none { it > 10 })
    println(list.all { it > 0 })
    println(list.fold(0) { acc, x -> acc + x })
    println(listOf(1, 2, 3).reduce { acc, x -> acc * x })
    println(list.count { it > 2 })
    println(list.first { it > 3 })
    println(list.last { it < 4 })
    println(list.find { it > 3 })
    println(list.find { it > 10 })
    println(listOf(3, 1, 4, 1, 5).sortedBy { it })
    println(listOf(1, 2, 3, 4, 5, 6).groupBy { it % 2 })
    val grouping: Grouping<Int, Int> = listOf(3, 1, 4, 2, 5).groupingBy { value: Int -> value % 2 }
    println(
        grouping.fold(
            initialValueSelector = { key: Int, element: Int -> key * 100 + element },
            operation = { key: Int, accumulator: Int, element: Int -> accumulator + key + element }
        )
    )
}
