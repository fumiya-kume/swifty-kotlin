fun main() {
    val list = listOf("a" to 1, "b" to 2, "c" to 3)
    val map = list.toMap()
    println(map)
    println(listOf("a" to 1, "b" to 2, "a" to 3).toMap())
}
