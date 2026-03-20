fun main() {
    val list = listOf(1, 2, 3, 4, 5, 6, 7)

    // chunked(size) — basic
    println(list.chunked(3))
    println(list.chunked(2))
    println(list.chunked(1))
    println(list.chunked(10))

    // String.chunked (no transform)
    println("abcdefg".chunked(3))
    println("abcdefg".chunked(2))
}
