fun buildString(x: Int): Int = x + 1

fun buildList(x: Int): Int = x + 2

fun buildMap(x: Int): Int = x + 3

fun main() {
    println(buildString(1))
    println(buildList(1))
    println(buildMap(1))
}
