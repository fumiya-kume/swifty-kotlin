fun main() {
    val list = listOf(1, 2, 3)
    println(list + 4)
    println(list + listOf(4, 5))
    println(list - 2)
    println(list - listOf(2, 3))
    println(list - setOf(1, 3))
    println(list)
}
