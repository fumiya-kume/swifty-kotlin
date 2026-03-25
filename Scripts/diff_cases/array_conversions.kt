fun main() {
    val arr = arrayOf(1, 2, 3)
    println(arr.toList())
    val list = listOf(4, 5, 6)
    val arr2 = list.toTypedArray()
    println(arr2.size)
    println(arr2[0])
}
