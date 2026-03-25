fun main() {
    val list = mutableListOf(3, 1, 4, 1, 5, 9, 2)
    list.sort()
    println(list)

    val words = mutableListOf("banana", "apple", "cherry")
    words.sortBy { it.length }
    println(words)

    words.sortByDescending { it.length }
    println(words)

    val numbers = mutableListOf(9, 10, 1, 20, 2)
    numbers.sortBy { it }
    println(numbers)

    numbers.sortByDescending { it }
    println(numbers)

}
