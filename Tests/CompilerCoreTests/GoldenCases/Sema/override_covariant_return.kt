package golden.sema

open class NumberContainer {
    open fun getValue(): Number = 42
    protected open fun getInternal(): String = "base"
}

open class IntContainer : NumberContainer() {
    // Covariant return type: Int is subtype of Number
    override fun getValue(): Int = 123
    // Visibility expansion: protected -> public
    public override fun getInternal(): String = "derived"
}

open class Animal {
    open fun makeSound(): String = "animal sound"
}

open class Dog : Animal() {
    override fun makeSound(): String = "woof"
}

fun main() {
    val c = IntContainer()
    println(c.getValue())
    println(c.getInternal())
    val dog = Dog()
    println(dog.makeSound())
}
