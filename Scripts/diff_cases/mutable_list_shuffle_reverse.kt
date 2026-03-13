fun main() {
    val list = mutableListOf(1, 2, 3, 4, 5)
    list.reverse()
    println(list)
    list.shuffle()
    println(list.sorted())

    val list2 = mutableListOf(1)
    list2.reverse()
    println(list2)
    list2.shuffle()
    println(list2.sorted())
}
