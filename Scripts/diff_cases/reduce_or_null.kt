fun main() {
    // reduce on non-empty list
    val sum = listOf(1, 2, 3, 4).reduce { acc, e -> acc + e }
    println(sum)

    // reduce with string concatenation
    val concat = listOf("a", "b", "c").reduce { acc, e -> acc + e }
    println(concat)

    // reduce on single-element list returns that element
    val single = listOf(42).reduce { acc, e -> acc + e }
    println(single)

    // reduce with multiplication
    val product = listOf(2, 3, 4).reduce { acc, e -> acc * e }
    println(product)

    // fold with initial value
    val foldSum = listOf(1, 2, 3).fold(0) { acc, e -> acc + e }
    println(foldSum)

    // fold on empty list returns initial value
    val foldEmpty = listOf<Int>().fold(0) { acc, e -> acc + e }
    println(foldEmpty)
}
