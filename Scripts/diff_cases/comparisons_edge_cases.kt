data class User(val name: String, val age: Int)

fun main() {
    println(compareValues(1, 2))
    println(compareValues(2, 2))
    println(compareValues(3, 2))

    val users = listOf(
        User("bob", 20),
        User("alice", 20),
        User("carol", 18),
    )
    val sorted = users.sortedWith(compareBy<User> { it.age }.thenBy { it.name })
    println(sorted.map { "${it.age}:${it.name}" })

    val nullable = listOf(2, null, 1)
    println(nullable.sortedWith(compareBy<Int?> { it }.nullsFirst()))
}
