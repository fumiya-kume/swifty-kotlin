fun main() {
    val a = listOf(1, 2, 3)
    val b = listOf("a", "b", "c")
    val zipped = a.zip(b)
    println(zipped)
    val (nums, strs) = zipped.unzip()
    println(nums)
    println(strs)
    println(listOf(1, 2).zip(listOf("x")))
    println(listOf<Pair<Int, String>>().unzip())
}
