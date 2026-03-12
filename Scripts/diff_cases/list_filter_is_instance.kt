fun main() {
    val mixed: List<Any> = listOf(1, "hello", 2, "world", 3)
    val strings = mixed.filterIsInstance<String>()
    println(strings)
    val ints = mixed.filterIsInstance<Int>()
    println(ints)

    val empty: List<Any> = listOf()
    println(empty.filterIsInstance<String>())
}
