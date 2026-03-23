fun main() {
    val list = listOf(1, 2, 3)
    println(list.singleOrNull())

    val single = listOf(42)
    println(single.singleOrNull())

    val empty = emptyList<Int>()
    println(empty.singleOrNull())
}
