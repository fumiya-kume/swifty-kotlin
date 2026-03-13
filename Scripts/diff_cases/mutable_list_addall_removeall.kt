fun main() {
    val list = mutableListOf(1, 2, 3)
    list.addAll(listOf(4, 5))
    println(list)

    list.removeAll(listOf(2, 4))
    println(list)

    list.retainAll(listOf(1, 5))
    println(list)
}
