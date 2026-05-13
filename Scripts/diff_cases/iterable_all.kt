fun main() {
    val values: Iterable<Int> = listOf(1, 2, 3, 4)
    println(values.all { it > 0 })
    println(values.all { it < 3 })

    val empty: Iterable<Int> = emptyList()
    println(empty.all { false })

    var calls = 0
    println(values.all {
        calls += 1
        it < 3
    })
    println(calls)

    val setValues: Iterable<Int> = setOf(1, 2)
    println(setValues.all { it < 3 })
}
