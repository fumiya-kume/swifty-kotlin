data class Person(val name: String, val age: Int)

fun main() {
    val people = listOf(
        Person("Alice", 30),
        Person("Bob", 25),
        Person("Alice", 25),
        Person("Bob", 30),
        Person("Charlie", 25)
    )

    // sortedBy name: stable sort by name ascending
    println("-- sortedBy name --")
    val byName = people.sortedBy { it.name }
    for (p in byName) {
        println("${p.name} ${p.age}")
    }

    // sortedBy age: stable sort by age ascending
    println("-- sortedBy age --")
    val byAge = people.sortedBy { it.age }
    for (p in byAge) {
        println("${p.name} ${p.age}")
    }

    // sortedWith on integers: ascending
    println("-- ascending --")
    println(listOf(3, 1, 4, 1, 5).sortedWith { a, b -> a - b })

    // sortedWith on integers: descending
    println("-- descending --")
    println(listOf(3, 1, 4, 1, 5).sortedWith { a, b -> b - a })

    // sortedByDescending on integers
    println("-- sortedByDescending --")
    println(listOf(3, 1, 4, 1, 5).sortedByDescending { it })
}
