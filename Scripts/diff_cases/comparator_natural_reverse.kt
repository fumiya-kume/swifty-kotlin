fun main() {
    val list = listOf(3, 1, 4, 1, 5, 9)
    println(list.sortedWith(naturalOrder()))
    println(list.sortedWith(reverseOrder()))
    val comp = compareBy<Int> { it }
    println(list.sortedWith(comp.reversed()))
}
