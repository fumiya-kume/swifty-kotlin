fun main() {
    val numbers = listOf(1, 2, 3, 4, 5)
    val strings = listOf("apple", "banana", "cherry")

    // firstOrNull() without predicate
    println(numbers.firstOrNull())

    // firstOrNull on strings
    println(strings.firstOrNull())

    // firstOrNull on single-element list
    val single = listOf(42)
    println(single.firstOrNull())

    // first() for comparison
    println(numbers.first())
    println(strings.first())
}
