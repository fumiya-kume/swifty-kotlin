fun main() {
    // Basic scanReduce on integers: cumulative sum
    val nums = listOf(1, 2, 3, 4, 5)
    val cumSum = nums.scanReduce { acc, element -> acc + element }
    println(cumSum)  // [1, 3, 6, 10, 15]

    // scanReduce on strings: progressive concatenation
    val words = listOf("a", "b", "c", "d")
    val concat = words.scanReduce { acc, element -> acc + element }
    println(concat)  // [a, ab, abc, abcd]

    // scanReduce with single element
    val single = listOf(42)
    val singleResult = single.scanReduce { acc, element -> acc + element }
    println(singleResult)  // [42]

    // scanReduce with multiplication
    val factors = listOf(1, 2, 3, 4)
    val products = factors.scanReduce { acc, element -> acc * element }
    println(products)  // [1, 2, 6, 24]

    // runningReduce produces the same result (scanReduce is its deprecated alias)
    val runResult = nums.runningReduce { acc, element -> acc + element }
    println(runResult)  // [1, 3, 6, 10, 15]
    println(cumSum == runResult)  // true
}
