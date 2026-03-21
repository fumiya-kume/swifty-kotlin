fun main() {
    // Basic associateWith on list of integers
    val numbers = listOf(1, 2, 3, 4, 5)
    println(numbers.associateWith { it * it })

    // associateWith on list of strings
    val words = listOf("hello", "world", "kotlin")
    println(words.associateWith { it.length })

    // associateWith returning string values
    val nums = listOf(1, 2, 3)
    println(nums.associateWith { "val_$it" })

    // associateWith on single element list
    val single = listOf(42)
    println(single.associateWith { it + 1 })

    // Chained: filter then associateWith
    println(numbers.filter { it > 2 }.associateWith { it * 3 })

    // Chained: map then associateWith
    println(numbers.map { it.toString() }.associateWith { it.length })
}
