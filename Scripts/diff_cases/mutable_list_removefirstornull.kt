fun main() {
    val values = mutableListOf(1, 2)

    println(values.removeFirstOrNull() ?: -1)
    println(values)
    println(values.removeFirstOrNull() ?: -1)
    println(values)
    println(values.removeFirstOrNull() ?: -1)
    println(values)
}
