// REFL-001: Basic type checks and class hierarchy
open class Animal
class Dog : Animal()
class Cat : Animal()

fun describe(a: Animal): String {
    return when (a) {
        is Dog -> "Dog"
        is Cat -> "Cat"
        else -> "Unknown"
    }
}

fun main() {
    println(describe(Dog()))
    println(describe(Cat()))
    println(Dog() is Animal)
    println(Cat() is Animal)
}
