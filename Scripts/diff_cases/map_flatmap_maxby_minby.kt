fun main() {
    val map = mapOf("a" to 1, "b" to 2, "c" to 3)
    println(map.flatMap { listOf(it.key, it.value.toString()) })
    println(map.maxByOrNull { it.value }?.key)
    println(map.minByOrNull { it.value }?.key)
    val emptyMap = emptyMap<String, Int>()
    println(emptyMap.maxByOrNull { it.value })

    // Additional maxByOrNull tests
    // maxByOrNull with key selector
    println(map.maxByOrNull { it.key })
    // minByOrNull with key selector
    println(map.minByOrNull { it.key })

    // maxByOrNull returning full entry
    val maxEntry = map.maxByOrNull { it.value }
    println(maxEntry)

    // minByOrNull returning full entry
    val minEntry = map.minByOrNull { it.value }
    println(minEntry)

    // maxByOrNull with negative values
    val negMap = mapOf("x" to -10, "y" to -1, "z" to -5)
    println(negMap.maxByOrNull { it.value })
    println(negMap.minByOrNull { it.value })

    // maxByOrNull with string length selector
    val strMap = mapOf(1 to "hello", 2 to "hi", 3 to "greetings")
    println(strMap.maxByOrNull { it.value.length })
    println(strMap.minByOrNull { it.value.length })

    // maxByOrNull on single-element map
    val singleMap = mapOf("only" to 42)
    println(singleMap.maxByOrNull { it.value })
    println(singleMap.minByOrNull { it.value })

    // emptyMap minByOrNull
    println(emptyMap.minByOrNull { it.value })

    // maxByOrNull with computed selector
    val wordMap = mapOf("apple" to 3, "banana" to 1, "cherry" to 2)
    println(wordMap.maxByOrNull { it.key.length + it.value })
    println(wordMap.minByOrNull { it.key.length + it.value })
}
