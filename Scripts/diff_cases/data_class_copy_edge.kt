// Basic class construction and property access
class Point(val x: Int, val y: Int)

fun main() {
    val p = Point(1, 2)
    println(p.x)
    println(p.y)

    val p2 = Point(10, 20)
    println(p2.x)
    println(p2.y)
}
