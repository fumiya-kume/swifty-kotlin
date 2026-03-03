sealed class Shape
class Circle : Shape()
class Rectangle : Shape()
class Triangle : Shape()

fun describeShape(s: Shape): String {
    return when (s) {
        is Circle -> "circle"
        is Rectangle -> "rectangle"
        is Triangle -> "triangle"
    }
}
