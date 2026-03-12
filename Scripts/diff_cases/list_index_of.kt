fun main() {
    val list = listOf(1, 2, 3, 2, 1)
    println(list.indexOf(2))
    println(list.indexOf(5))
    println(list.lastIndexOf(2))
    println(list.lastIndexOf(5))
    println(list.indexOfFirst { it > 2 })
    println(list.indexOfFirst { it > 5 })
    println(list.indexOfLast { it < 3 })
    println(list.indexOfLast { it > 5 })
}
