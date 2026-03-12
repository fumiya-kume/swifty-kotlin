fun main() {
    val list = listOf(1, 2, 3, 4, 5, 6)
    val (evens, odds) = list.partition { it % 2 == 0 }
    println(evens)
    println(odds)

    val empty = listOf<Int>()
    val (a, b) = empty.partition { it > 0 }
    println(a)
    println(b)
}
