fun sum(vararg nums: Int): Int = nums.sum()
fun printAll(vararg items: String) { for (item in items) println(item) }
fun main() {
    println(sum(1, 2, 3))
    val arr = intArrayOf(4, 5, 6)
    println(sum(*arr))
    println(sum(1, *arr, 7))
    printAll("a", "b", "c")
    val strs = arrayOf("x", "y")
    printAll(*strs)
}
// SKIP-DIFF: spread vararg parity pending
