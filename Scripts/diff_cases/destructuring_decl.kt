data class Point(val x: Int, val y: Int)

fun main() {
    val p = Point(10, 20)
    val (a, b) = p
    println(a)
    println(b)

    val (_, second) = Point(3, 4)
    println(second)
}
