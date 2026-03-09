fun main() {
    val values = listOf("a", "bb")
    values.forEachIndexed { index, value ->
        println(index)
        println(value)
    }
    println(values.mapIndexed { index, value -> index + value.length })
}
