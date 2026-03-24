data class Point(val x: Int, val y: Int)
fun main() {
    val (x, y) = Point(3, 4)
    println("$x, $y")
    val map = mapOf("a" to 1, "b" to 2)
    for ((key, value) in map) println("$key=$value")
    val (first, second, third) = Triple(10, 20, 30)
    println("$first $second $third")
    val list = listOf(100, 200, 300)
    val (a, b, c) = list
    println("$a $b $c")
}
