fun main() {
    val values = listOf(10, 20)
    values.forEachIndexed { index, value -> println(index * 100 + value) }
    println(values.mapIndexed { index, value -> index + value })
}
