fun main() {
    // Simple flatten tests
    println(listOf(listOf(1, 2), listOf(3, 4)).flatten())
    println(listOf<Int>().flatten())
    println(listOf(listOf<Int>()).flatten())
}
