class Greeter(val greeting: String) {
    fun greet(name: String): String = greeting + " " + name
}

fun main() {
    val g = Greeter("Hello")
    println(g.greet("World"))
}
