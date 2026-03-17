fun main() {
    data class Person(val name: String, val age: Int)
    val people = listOf(Person("Charlie", 30), Person("Alice", 25), Person("Bob", 25))
    val sorted = people.sortedWith(compareBy({ it.name.length }, { it.name }))
    sorted.forEach { println("${it.name} ${it.age}") }
}
