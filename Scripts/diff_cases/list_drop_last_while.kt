fun main() {
    val list = listOf(1, 2, 3, 4, 5)
    println(list.dropLastWhile { it > 3 })
    println(list.dropLastWhile { it < 10 })
    println(list.dropLastWhile { it == 0 })
    println(emptyList<Int>().dropLastWhile { it > 0 })
}
