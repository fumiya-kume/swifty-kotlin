fun main() {
    val nested = listOf(listOf(1, 2), listOf(3, 4), listOf(5))
    println(nested.flatten())
    println(listOf(listOf<Int>(), listOf(1), listOf<Int>()).flatten())
    val strings = listOf(listOf("a", "b"), listOf("c"))
    println(strings.flatten())
    val single = listOf(listOf(99))
    println(single.flatten())
}
