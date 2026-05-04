fun main() {
    val values: Iterable<Int> = listOf(1, 2, 3)

    println(values.sumByDouble { value ->
        if (value == 2) 1.5 else 0.25
    })
    println(listOf(7).sumByDouble { value ->
        value.toDouble() + 0.5
    })
    println(emptyList<Int>().sumByDouble { 5.0 })
}
