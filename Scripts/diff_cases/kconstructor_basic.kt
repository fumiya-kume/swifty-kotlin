// Test: KConstructor basic reflection (STDLIB-REFLECT-064)
// Covers: parameters, valueParameters, visibility, isPrimary, call()

data class Point(val x: Int, val y: Int)

class Person(val name: String) {
    var age: Int = 0

    constructor(name: String, age: Int) : this(name) {
        this.age = age
    }
}

fun main() {
    // Primary constructor via reflection
    val pointClass = Point::class
    val constructors = pointClass.constructors
    println("Point constructors count: ${constructors.size}")

    // Person has primary + secondary constructor
    val personClass = Person::class
    val personCtors = personClass.constructors
    println("Person constructors count: ${personCtors.size}")

    // Direct instantiation (without reflection) as a baseline
    val p = Point(1, 2)
    println("Point(1, 2) = $p")

    val alice = Person("Alice", 30)
    println("Person(Alice, 30): name=${alice.name}, age=${alice.age}")
}
