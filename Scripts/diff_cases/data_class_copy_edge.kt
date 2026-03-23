// Data class copy() edge cases:
// - simple data class
// - data class with default values
// - data class with many parameters

data class Point(val x: Int, val y: Int)

data class User(val name: String, val age: Int = 25)

data class Config(
    val host: String,
    val port: Int,
    val secure: Boolean,
    val timeout: Long,
    val label: String
)

fun main() {
    // Simple copy
    val p = Point(1, 2)
    val p2 = p.copy()
    println(p2.x)
    println(p2.y)

    // Copy with partial override
    val p3 = p.copy(x = 10)
    println(p3.x)
    println(p3.y)

    // Copy with all overrides
    val p4 = p.copy(x = 100, y = 200)
    println(p4.x)
    println(p4.y)

    // Default values — copy preserves them
    val u = User("Alice")
    val u2 = u.copy()
    println(u2.name)
    println(u2.age)

    // Override the default-valued parameter
    val u3 = u.copy(age = 30)
    println(u3.name)
    println(u3.age)

    // Many parameters
    val c = Config("localhost", 8080, true, 5000L, "dev")
    val c2 = c.copy(port = 9090, label = "prod")
    println(c2.host)
    println(c2.port)
    println(c2.secure)
    println(c2.timeout)
    println(c2.label)
}
