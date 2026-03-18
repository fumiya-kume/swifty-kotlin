fun main() {
    data class Person(val name: String, val age: Int)
    val people = listOf(Person("Alice", 30), Person("Bob", 25), Person("Alice", 25))
    println("-- thenBy --")
    val sorted = people.sortedWith(compareBy<Person> { it.name }.thenBy { it.age })
    sorted.forEach { println("${it.name} ${it.age}") }
    println("-- thenByDescending --")
    val sortedDesc = people.sortedWith(compareBy<Person> { it.name }.thenByDescending { it.age })
    sortedDesc.forEach { println("${it.name} ${it.age}") }
}
