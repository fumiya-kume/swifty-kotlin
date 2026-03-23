fun main() {
    // Zip two lists together
    val nums = listOf(1, 2, 3)
    val strs = listOf("a", "b", "c")
    val zipped = nums.zip(strs)
    println(zipped)

    // Zip lists of different lengths (truncates to shorter)
    val long = listOf(1, 2, 3, 4, 5)
    val short = listOf("x", "y")
    println(long.zip(short))

    // Zip with single element lists
    val s1 = listOf(42)
    val s2 = listOf("hello")
    println(s1.zip(s2))
}
