fun main() {
    val values: Iterable<Int> = listOf(1, 2, 2, 3, 4)
    println(values.minus(sequenceOf(2, 4)))
    println(values.minus(arrayOf(2, 4)))
    println(values.minus(2))
    println(values.minus(listOf(2, 4)))
    println(values)

    val nullable: Iterable<String?> = listOf("x", null, "x", "y")
    val nullableArray: Array<out String?> = arrayOf(null)
    val nullableSequence: Sequence<String?> = sequenceOf("x", null)
    println(nullable.minus(nullableArray))
    println(nullable.minus(nullableSequence))

    val emptyArrayOf: Array<Int> = emptyArray()
    println(emptyArray<Int>().let { values.minus(it) })
    println(values.minus(emptySequence<Int>()))
    println(values.minus(emptyArrayOf))

    fun arrayIsEmptyBranch(elements: Array<out Int>): Int {
        return if (elements.isEmpty()) 1 else 2
    }
    println(arrayIsEmptyBranch(arrayOf(1)))
    println(arrayIsEmptyBranch(emptyArray<Int>()))
}
