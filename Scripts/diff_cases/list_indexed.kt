fun main() {
    val values = listOf(10, 20)
    println(values.withIndex())
    values.forEachIndexed { index, value -> println(index + value) }
    println(values.mapIndexed { index, value -> index + value })
}
