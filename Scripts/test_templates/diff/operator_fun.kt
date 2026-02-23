data class Vec(val x: Int, val y: Int) {
    operator fun plus(other: Vec) = Vec(x + other.x, y + other.y)
    operator fun unaryMinus() = Vec(-x, -y)
}

fun main() {
    val a = Vec(1, 2)
    val b = Vec(3, 4)
    println(a + b)
    println(-a)
}
