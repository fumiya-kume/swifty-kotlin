fun main() {
    val x = 10
    val nums = listOf(1, 2, 3, 4, 5)

    // Capture in map
    println(nums.map { it + x })

    // Capture in filter
    val threshold = 3
    println(nums.filter { it > threshold })

    // Capture in forEach
    val prefix = "val="
    nums.forEach { println(prefix + it.toString()) }
}
