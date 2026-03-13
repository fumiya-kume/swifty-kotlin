fun main() {
    val words = listOf("a", "bbb", "cc")
    println(words.maxByOrNull { it.length })
    println(words.minByOrNull { it.length })
    println(words.maxOfOrNull { it.length })
    println(words.minOfOrNull { it.length })

    val emptyWords = emptyList<String>()
    println(emptyWords.maxByOrNull { it.length })
    println(emptyWords.minByOrNull { it.length })
    println(emptyWords.maxOfOrNull { it.length })
    println(emptyWords.minOfOrNull { it.length })
    println(words.maxOfOrNull { it.length })
    println(words.minOfOrNull { it.length })

    val emptyWords = emptyList<String>()
    println(emptyWords.maxByOrNull { it.length })
    println(emptyWords.minByOrNull { it.length })
    println(emptyWords.maxOfOrNull { it.length })
    println(emptyWords.minOfOrNull { it.length })
}
