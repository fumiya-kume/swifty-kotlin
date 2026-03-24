abstract class Shape {
    abstract fun area(): Double
    open fun describe(): String = "I am a shape"
}
class Circle(val r: Double) : Shape() {
    override fun area(): Double = 3.14159 * r * r
    override fun describe(): String = "Circle"
}
class Rect(val w: Double, val h: Double) : Shape() {
    override fun area(): Double = w * h
}
fun main() {
    val c = Circle(5.0)
    println(c.describe())
    println(c.area())
    val r = Rect(3.0, 4.0)
    println(r.describe())
    println(r.area())
}
