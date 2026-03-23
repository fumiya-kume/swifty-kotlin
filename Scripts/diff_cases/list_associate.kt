fun main() {
    // associateWith: each element becomes the key, lambda gives value
    val numbers = listOf(1, 2, 3, 4, 5)
    println(numbers.associateWith { it * it })

    val words = listOf("apple", "banana", "cherry")
    println(words.associateWith { it.length })

    // associateWith on single element
    val single = listOf(42)
    println(single.associateWith { it + 1 })

    // associateWith with string values
    val ints = listOf(10, 20, 30)
    println(ints.associateWith { it - 5 })

    // Chaining: filter then associateWith
    println(numbers.filter { it > 2 }.associateWith { it * 3 })
}
