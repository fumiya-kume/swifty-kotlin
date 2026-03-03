abstract class Shape {
    abstract fun area(): Double
}

class Circle(val radius: Double) : Shape() {
    override fun area(): Double = 3.14 * radius * radius
}

fun main() {
    val c = Circle(5.0)
    println(c.area())
}
