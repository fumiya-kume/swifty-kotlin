// Edge cases for data class copy()
// 1. Normal data class copy
data class Point(val x: Int, val y: Int)

// 2. Single-property data class
data class Name(val value: String)

// 3. Data class with many properties
data class Person(val name: String, val age: Int, val active: Boolean)

fun main() {
    // Normal copy
    val p = Point(1, 2)
    val p2 = p.copy()
    println(p2.x)  // 1
    println(p2.y)  // 2

    // Copy with named arguments
    val p3 = p.copy(x = 10)
    println(p3.x)  // 10
    println(p3.y)  // 2

    // Single-property copy
    val n = Name("hello")
    val n2 = n.copy(value = "world")
    println(n2.value) // world

    // Multi-property copy
    val person = Person("Alice", 30, true)
    val person2 = person.copy(age = 31)
    println(person2.name)   // Alice
    println(person2.age)    // 31
    println(person2.active) // true

    // Copy returns a new instance
    val p4 = p.copy()
    println(p4 == p)  // true (structural equality)
}
