fun main() {
    val values: Iterable<Int> = listOf(1, 2, 2, 3)

    println(values.minusElement(2))
    println(values.minusElement(9))
    println(emptyList<Int>().minusElement(1))
}
