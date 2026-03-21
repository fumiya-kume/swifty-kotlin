fun main() {
    // Basic runningFold with Int accumulator
    val nums = listOf(1, 2, 3, 4)
    val sums = nums.runningFold(0) { acc, x -> acc + x }
    println(sums) // [0, 1, 3, 6, 10]

    // runningFold with String accumulator
    val words = listOf("a", "b", "c")
    val concat = words.runningFold("") { acc, s -> acc + s }
    println(concat) // [, a, ab, abc]

    // runningFold on empty list
    val empty = emptyList<Int>()
    val emptyResult = empty.runningFold(42) { acc, x -> acc + x }
    println(emptyResult) // [42]

    // runningFold with different accumulator type
    val lengths = listOf("hello", "world", "!").runningFold(0) { acc, s -> acc + s.length }
    println(lengths) // [0, 5, 10, 11]

    // runningFold with single element
    val single = listOf(100).runningFold(0) { acc, x -> acc + x }
    println(single) // [0, 100]

    // runningFold with multiplication
    val products = listOf(1, 2, 3, 4).runningFold(1) { acc, x -> acc * x }
    println(products) // [1, 1, 2, 6, 24]
}
