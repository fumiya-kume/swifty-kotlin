fun main() {
    // Two captures in map
    val base = 100
    val scale = 2
    println(listOf(1, 2, 3).map { it * scale + base })

    // Two captures in filter
    val lo = 2
    val hi = 4
    println(listOf(1, 2, 3, 4, 5).filter { it >= lo && it <= hi })

    // Three captures in map
    val a = 1
    val b = 10
    val c = 100
    println(listOf(1, 2, 3).map { it + a + b + c })

    // Two captures in forEach
    val tag = "item"
    val sep = ": "
    listOf(1, 2, 3).forEach { println(tag + sep + it.toString()) }

    // Two captures in any/all/none
    val min = 2
    val max = 4
    println(listOf(1, 2, 3, 4, 5).any { it >= min && it <= max })
    println(listOf(1, 2, 3, 4, 5).all { it >= min && it <= max })
    println(listOf(1, 2, 3, 4, 5).none { it >= min && it <= max })
}
