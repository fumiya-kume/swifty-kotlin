fun main() {
    val numbers = listOf(1, 2, 3)
    val letters = listOf("a", "b", "c")
    val zipped = numbers.zip(letters)
    println(zipped)
    val (nums, strs) = zipped.unzip()
    println(nums)
    println(strs)
    println(listOf(1, 2).zip(listOf("x")))
    println(listOf<Pair<Int, String>>().unzip())
}
