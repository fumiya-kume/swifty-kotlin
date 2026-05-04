fun main() {
    val values: Iterable<Int> = listOf(1, 2, 3)

    println(values.sumBy { value ->
        value * value
    })
    println(listOf(7).sumBy { value ->
        value * 3
    })
    println(emptyList<Int>().sumBy { 5 })
}
