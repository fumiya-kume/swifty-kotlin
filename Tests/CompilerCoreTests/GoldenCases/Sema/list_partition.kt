fun main() {
    val list = listOf(1, 2, 3, 4, 5)
    val (evens, odds) = list.partition { it % 2 == 0 }
    println(evens)
    println(odds)
}
