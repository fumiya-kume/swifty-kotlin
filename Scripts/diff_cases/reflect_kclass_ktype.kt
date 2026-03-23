// REFL-005: kotlin.reflect KClass members and KType
open class Animal
class Dog : Animal()
class Cat : Animal()

fun main() {
    val dog = Dog()
    val cat = Cat()

    // KClass.isInstance
    val dogClass = Dog::class
    println(dogClass.isInstance(dog))   // true
    println(dogClass.isInstance(cat))   // false
    println(dogClass.isInstance(42))    // false

    // KClass.constructors returns a collection
    val constructors = Dog::class.constructors
    println(constructors.size)         // 1
}
