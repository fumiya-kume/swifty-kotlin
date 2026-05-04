fun main() {
    val values = mutableListOf(1, 2)

    println(values.removeLastOrNull() ?: -1)
    println(values)
    println(values.removeLastOrNull() ?: -1)
    println(values)
    println(values.removeLastOrNull() ?: -1)
    println(values)
}
