fun main() {
    val list = listOf(1, 2, 3, 4, 5)
    println(list.takeLast(3))
    println(list.dropLast(2))
    println(list.takeLast(0))
    println(list.dropLast(0))
    println(list.takeLast(10))
    println(list.dropLast(10))
}
