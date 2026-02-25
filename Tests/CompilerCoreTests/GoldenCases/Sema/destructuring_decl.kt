data class Point(val x: Int, val y: Int)

fun basicDestructuring() {
    val p = Point(1, 2)
    val (a, b) = p
    println(a)
    println(b)
}

fun destructuringWithUnderscore() {
    val p = Point(3, 4)
    val (_, second) = p
    println(second)
}
