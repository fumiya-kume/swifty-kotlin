fun main() {
    val nums = listOf(231, 114, 123, 212, 111, 223, 214)

    println("-- compareBy + thenBy --")
    val byModThen = compareBy<Int> { it % 10 }.thenBy { it / 10 }
    println(nums.sortedWith(byModThen))

    println("-- compareBy + thenByDescending --")
    val byModThenDescending = compareBy<Int> { it % 10 }.thenByDescending { it / 10 }
    println(nums.sortedWith(byModThenDescending))

    println("-- compareBy + thenDescending --")
    val byModThenComparatorDescending = compareBy<Int> { it % 10 }.thenDescending(compareBy<Int> { it / 10 })
    println(nums.sortedWith(byModThenComparatorDescending))

    println("-- sortedBy + sortedBy chain --")
    println(nums.sortedBy { it % 10 }.sortedBy { it / 10 })

    println("-- sortedByDescending + sortedBy chain --")
    println(nums.sortedByDescending { it % 10 }.sortedBy { it / 10 })

    val nullableNums = listOf(14, null, 3, null, 25, 17, 4)

    println("-- nullsFirst --")
    println(nullableNums.sortedWith(compareBy<Int?> { it }.nullsFirst()))

    println("-- nullsLast --")
    println(nullableNums.sortedWith(compareBy<Int?> { it }.nullsLast()))

    println("-- naturalOrder + reverseOrder --")
    val words = listOf("pear", "apple", "orange", "fig")
    println(words.sortedWith(naturalOrder()))
    println(words.sortedWith(reverseOrder()))

    println("-- comparator.reversed() chain --")
    val reversedChain = compareBy<Int> { it % 10 }.thenBy { it / 10 }.reversed()
    println(nums.sortedWith(reversedChain))
}
