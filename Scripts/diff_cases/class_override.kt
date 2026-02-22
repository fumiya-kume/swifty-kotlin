open class Animal {
    open fun speak(): Int = 0
}

class Dog : Animal() {
    override fun speak(): Int = 1
}

class Cat : Animal() {
    override fun speak(): Int = 2
}

fun describeAnimal(a: Animal): Int = a.speak()

fun main() {
    val dog = Dog()
    val cat = Cat()
    println(describeAnimal(dog))
    println(describeAnimal(cat))
}
