fun main() {
    val list = listOf(1, 2, 3)
    println(list.firstOrNull())
    println(list.lastOrNull())
    val empty = emptyList<Int>()
    println(empty.firstOrNull())
    println(empty.lastOrNull())
}
