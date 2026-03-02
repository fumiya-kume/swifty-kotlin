abstract class A {
    abstract fun f()
}

class B : A() {
    override fun f() = println("B.f")
}

abstract class Animal {
    abstract fun speak()
}

abstract class Pet : Animal() {
    abstract fun name()
}

class Dog : Pet() {
    override fun speak() = println("woof")
    override fun name() = println("dog")
}

fun main() {
    val b = B()
    b.f()
    val d = Dog()
    d.speak()
    d.name()
}
