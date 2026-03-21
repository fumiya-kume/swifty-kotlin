fun main() {
    // Basic runningReduce on List<Int>
    val nums = listOf(1, 2, 3, 4, 5)
    println(nums.runningReduce { acc, x -> acc + x })

    // runningReduce with multiplication
    println(listOf(1, 2, 3, 4).runningReduce { acc, x -> acc * x })

    // runningReduce on single-element list
    println(listOf(42).runningReduce { acc, x -> acc + x })

    // runningReduce on strings
    val words = listOf("a", "b", "c", "d")
    println(words.runningReduce { acc, x -> acc + x })

    // runningReduce with max logic
    println(listOf(3, 1, 4, 1, 5, 9, 2, 6).runningReduce { acc, x -> if (x > acc) x else acc })
}
