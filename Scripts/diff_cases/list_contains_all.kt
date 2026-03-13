fun main() {
    val list = listOf(1, 2, 3, 4, 5)
    println(list.containsAll(listOf(1, 3)))
    println(list.containsAll(listOf(1, 6)))
    println(list.containsAll(emptyList()))
}
