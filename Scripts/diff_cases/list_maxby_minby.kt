fun main() {
    val words = listOf("a", "bbb", "cc")
    println(words.maxByOrNull { it.length })
    println(words.minByOrNull { it.length })
}
