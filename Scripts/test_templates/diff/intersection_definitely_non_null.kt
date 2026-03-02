fun idTag(x: String): Int = 7

fun safeTag(x: String): Int = idTag(x)

fun main() {
    println(safeTag("hello"))
    println(safeTag("world"))
}
