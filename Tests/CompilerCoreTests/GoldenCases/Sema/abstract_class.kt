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
    abstract val species: String
}

abstract class Pet : Animal() {
    abstract fun petName(): String
    abstract val owner: String
}

class Dog : Pet() {
    override fun speak(): String = "woof"
    override fun petName(): String = "dog"
    override val species: String = "canine"
    override val owner: String = "human"
}

// Test abstract var property
abstract class Container {
    abstract var items: List<String>
}

class Box : Container() {
    override var items: List<String> = emptyList()
}
