fun main() {
    // associateWith on list of strings (key = element, value = transform)
    val words = listOf("apple", "banana", "cherry")
    println(words.associateWith { it.length })

    // associateWith on list of integers
    val numbers = listOf(1, 2, 3, 4, 5)
    println(numbers.associateWith { it * it })

    // associateWith on single element
    val single = listOf("hello")
    println(single.associateWith { it.length })

    // associateWith with string values
    val nums = listOf(1, 2, 3)
    println(nums.associateWith { "val_$it" })

    // Chaining: filter then associateWith
    println(numbers.filter { it > 2 }.associateWith { it * 3 })
}
