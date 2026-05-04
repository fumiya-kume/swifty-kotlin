fun main() {
    val values = mutableListOf(3, 1, 4)
    values.sortWith { a, b -> a - b }
    println(values)

    values.sortWith(compareByDescending<Int> { it })
    println(values)

    val words = mutableListOf("pear", "fig", "apple")
    words.sortWith(compareBy<String> { it.length })
    println(words)
}
