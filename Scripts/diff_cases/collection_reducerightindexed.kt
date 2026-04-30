fun main() {
    val values: Iterable<Int> = listOf(1, 2, 3)

    println(values.reduceRightIndexed { index, value, acc ->
        index * 100 + value * 10 + acc
    })
    println(listOf(7).reduceRightIndexed { index, value, acc ->
        index + value + acc
    })

    try {
        println(emptyList<Int>().reduceRightIndexed { index, value, acc ->
            index + value + acc
        })
    } catch (e: Throwable) {
        println("empty")
    }
}
