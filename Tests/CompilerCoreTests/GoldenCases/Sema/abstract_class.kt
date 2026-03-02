package golden.sema

abstract class Shape {
    abstract fun area(): Double
    abstract val name: String
    fun description(): String = "shape"
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
    override fun petName(): String = "dog"
}
