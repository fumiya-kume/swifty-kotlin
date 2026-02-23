fun printFirst(list: List<*>) {
    println(list[0])
}

fun main() {
    printFirst(listOf(1, 2, 3))
    printFirst(listOf("a", "b"))
}
