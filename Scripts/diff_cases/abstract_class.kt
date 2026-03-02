abstract class Shape {
    abstract fun area(): Double
    abstract val name: String
    fun description(): String = name
}

class Circle(val radius: Double) : Shape() {
    override fun area(): Double = 3.14 * radius * radius
    override val name: String = "circle"
}

abstract class Animal {
    abstract fun speak(): String
}

abstract class Pet : Animal() {
    abstract fun petName(): String
}

class Dog : Pet() {
    override fun speak(): String = "woof"
    override fun petName(): String = "buddy"
}

fun main() {
    val c = Circle(5.0)
    println(c.area())
    println(c.name)
    println(c.description())
    val d = Dog()
    println(d.speak())
    println(d.petName())
}
