fun main() {
    val nested = listOf(listOf(1, 2), listOf(3, 4), listOf(5))
    println(nested.flatten())

    val empty = listOf(listOf<Int>(), listOf<Int>())
    println(empty.flatten())

    val single = listOf(listOf(1, 2, 3))
    println(single.flatten())
}
