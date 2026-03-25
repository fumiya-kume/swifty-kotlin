abstract class A {
    abstract fun f()
    abstract val name: String
}

class B : A() {
    override fun f() = println("B.f")
    override val name: String = "B"
}

abstract class Animal {
    abstract fun speak()
    abstract val species: String
}

abstract class Pet : Animal() {
    abstract fun name()
    abstract val owner: String
}

class Dog : Pet() {
    override fun speak() = println("woof")
    override fun name() = println("dog")
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

// Test empty abstract class (should generate warning)
abstract class EmptyAbstract {
    fun someMethod() {}
}

fun main() {
    val b = B()
    b.f()
    val d = Dog()
    d.speak()
    d.name()

    val box = Box()
    println(box.items)
}
