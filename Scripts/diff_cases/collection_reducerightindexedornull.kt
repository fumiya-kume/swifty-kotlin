fun main() {
    val values: List<Int> = listOf(1, 2, 3)

    println(values.reduceRightIndexedOrNull { index, value, acc ->
        index * 100 + value * 10 + acc
    } ?: -1)
    println(listOf(7).reduceRightIndexedOrNull { index, value, acc ->
        index + value + acc
    } ?: -1)
    println(emptyList<Int>().reduceRightIndexedOrNull { index, value, acc ->
        index + value + acc
    } ?: -1)
}
