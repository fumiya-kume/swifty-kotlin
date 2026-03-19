fun main() {
    val list = listOf(1, 2, 3, 4, 5, 6, 7)
    println(list.chunked(3))
    println(list.windowed(3, 1))
    println(list.windowed(3, 2))
    println(list.windowed(3, 2, true))

    // String.windowed regression (STDLIB-549)
    val s = "abcdefgh"
    println(s.windowed(3, 1))
    println(s.windowed(3, 2))
    println(s.windowed(3, 2, true))
}
