fun main() {
    val list = listOf(1, 2, 3, 4, 5)
    val result = list.asSequence()
        .filter { it % 2 != 0 }
        .map { it * 10 }
        .toList()
    println(result)
    // Exercise asSequence on another list
    val nums = listOf(10, 20, 30, 40, 50)
    val result2 = nums.asSequence()
        .filter { it % 20 == 0 }
        .toList()
    println(result2)
}
