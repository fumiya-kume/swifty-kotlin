fun main() {
    val values: Iterable<Int> = listOf(1, 2, 3, 4)
    println(values.any())
    println(values.any { it > 2 })
    println(values.any { it > 9 })

    val empty: Iterable<Int> = emptyList()
    println(empty.any())
    println(empty.any { true })

    var calls = 0
    println(values.any {
        calls += 1
        it > 2
    })
    println(calls)

    val setValues: Iterable<Int> = setOf(1, 2)
    println(setValues.any { it == 2 })
}
