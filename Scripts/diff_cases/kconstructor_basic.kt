// SKIP-DIFF
// STDLIB-REFLECT-064: KConstructor complete implementation
class Simple

data class Person(val name: String, val age: Int)

class WithSecondary(val x: Int) {
    constructor() : this(0)
}

fun main() {
    // KClass.constructors returns a collection
    val personClass = Person::class
    val constructors = personClass.constructors
    println("Person constructors count: ${constructors.size}")

    // KClass.primaryConstructor
    val primaryCtor = personClass.primaryConstructor
    println("Person has primary constructor: ${primaryCtor != null}")

    // Simple class constructors
    val simpleClass = Simple::class
    val simpleCtors = simpleClass.constructors
    println("Simple constructors count: ${simpleCtors.size}")

    // WithSecondary has both primary and secondary constructors
    val wsClass = WithSecondary::class
    val wsCtors = wsClass.constructors
    println("WithSecondary constructors count: ${wsCtors.size}")
}
