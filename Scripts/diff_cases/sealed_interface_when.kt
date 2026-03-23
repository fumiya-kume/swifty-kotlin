sealed interface Shape
data class Circle(val radius: Double) : Shape
data class Rectangle(val w: Double, val h: Double) : Shape

fun area(shape: Shape): Double = when (shape) {
    is Circle -> 3.14 * shape.radius * shape.radius
    is Rectangle -> shape.w * shape.h
}

fun main() {
    println(area(Circle(5.0)))
    println(area(Rectangle(3.0, 4.0)))
}
