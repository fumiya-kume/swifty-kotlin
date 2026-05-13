fun main() {
    val words = listOf("apple", "banana", "cherry")
    println(words.associateBy { it.length })

    val numbers = listOf(1, 2, 3, 4)
    println(numbers.associateBy { it % 2 })
    println(numbers.associateBy({ it % 2 }, { it * 10 }))

    val single = listOf("hello")
    println(single.associateBy { it.length })

    val empty = emptyList<Int>()
    println(empty.associateBy { it })

    println(numbers.filter { it > 2 }.associateBy { it % 2 })
}
