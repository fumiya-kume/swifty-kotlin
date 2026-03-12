fun main() {
    val list = listOf(1, 2, 3, 4, 5)
    println(list.chunked(2))
    println(list.chunked(3))
    println(list.chunked(1))
    println(list.chunked(6))

    println(list.windowed(3, 1))
    println(list.windowed(2, 2))
    println(list.windowed(3, 2))
}
