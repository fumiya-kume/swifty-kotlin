fun main() {
    val ints = listOf(1, 2, 3)
    val arr = ints.toIntArray()
    println(arr.size)          // 3
    println(arr[0])            // 1
    println(arr.toList())      // [1, 2, 3]

    val longs = listOf(100L, 200L)
    val larr = longs.toLongArray()
    println(larr.size)         // 2

    val bytes = listOf<Byte>(10, 20, 30)
    val barr = bytes.toByteArray()
    println(barr.size)         // 3
}
