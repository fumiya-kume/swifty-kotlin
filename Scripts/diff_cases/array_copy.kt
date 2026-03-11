fun main() {
    val arr = arrayOf(1, 2, 3)
    val copy = arr.copyOf()
    println(copy.toList())
    println(arr.copyOfRange(0, 2).toList())
}
