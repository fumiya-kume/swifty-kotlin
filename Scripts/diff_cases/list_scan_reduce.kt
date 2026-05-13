fun main() {
    // Basic runningReduce on integers: cumulative sum
    val nums = listOf(1, 2, 3, 4, 5)
    val cumSum = nums.runningReduce { acc, element -> acc + element }
    println(cumSum)  // [1, 3, 6, 10, 15]

    // runningReduce on strings: progressive concatenation
    val words = listOf("a", "b", "c", "d")
    val concat = words.runningReduce { acc, element -> acc + element }
    println(concat)  // [a, ab, abc, abcd]

    // runningReduce with single element
    val single = listOf(42)
    val singleResult = single.runningReduce { acc, element -> acc + element }
    println(singleResult)  // [42]

    // runningReduce with multiplication
    val factors = listOf(1, 2, 3, 4)
    val products = factors.runningReduce { acc, element -> acc * element }
    println(products)  // [1, 2, 6, 24]

    // runningReduce cumulative sum again for comparison
    val runResult = nums.runningReduce { acc, element -> acc + element }
    println(runResult)  // [1, 3, 6, 10, 15]
    println(cumSum == runResult)  // true
}
