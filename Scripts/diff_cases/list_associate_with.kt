fun main() {
    // Basic associateWith on list of integers
    val numbers = listOf(1, 2, 3, 4, 5)
    println(numbers.associateWith { it * it })

    // associateWith on list of strings
    val words = listOf("hello", "world", "kotlin")
    println(words.associateWith { it.length })

    // associateWith with duplicate-free keys (each element is unique key)
    val chars = listOf('a', 'b', 'c')
    println(chars.associateWith { it.code })

    // associateWith on empty list
    val empty = emptyList<Int>()
    println(empty.associateWith { it * 2 })

    // associateWith returning string values
    val nums = listOf(1, 2, 3)
    println(nums.associateWith { "val_$it" })

    // associateWith returning boolean values
    println(nums.associateWith { it % 2 == 0 })

    // associateWith on single element list
    val single = listOf(42)
    println(single.associateWith { it + 1 })

    // associateWith with nullable values
    println(nums.associateWith { if (it % 2 == 0) it * 10 else null })

    // Chained: filter then associateWith
    println(numbers.filter { it > 2 }.associateWith { it * 3 })

    // Chained: map then associateWith
    println(numbers.map { it.toString() }.associateWith { it.length })
}
