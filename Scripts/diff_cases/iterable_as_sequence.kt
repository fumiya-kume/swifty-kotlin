fun main() {
    val list = listOf(1, 2, 3, 4, 5)
    val result = list.asSequence()
        .filter { it % 2 != 0 }
        .map { it * 10 }
        .toList()
    println(result)
}
