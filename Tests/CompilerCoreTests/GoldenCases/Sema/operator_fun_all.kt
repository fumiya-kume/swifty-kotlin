package golden.sema

class Vec(x0: Int, y0: Int) {
    val x: Int = x0
    val y: Int = y0

    operator fun plus(other: Vec): Vec = Vec(x + other.x, y + other.y)
    operator fun minus(other: Vec): Vec = Vec(x - other.x, y - other.y)
    operator fun times(scalar: Int): Vec = Vec(x * scalar, y * scalar)
    operator fun unaryMinus(): Vec = Vec(-x, -y)
    operator fun get(index: Int): Int = if (index == 0) x else y
}

fun useOperators() {
    val a = Vec(1, 2)
    val b = Vec(3, 4)
    val c = a + b
    val d = a - b
    val e = a * 2
    val f = -a
    val g = a[0]
}
