data class Person(val name: String, val age: Int)

fun main() {
    val people = listOf(
        Person("Alice", 25),
        Person("Bob", 30),
        Person("Charlie", 35),
        Person("David", 40),
    )

    println(people.binarySearchBy(35) { it.age })
    println(people.binarySearchBy(35, 1) { it.age })
    println(people.binarySearchBy(35, 1, 4) { it.age })
    println(people.binarySearchBy(28) { it.age })
}
