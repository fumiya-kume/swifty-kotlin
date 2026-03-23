fun double(x: Int): Int = x * 2
fun add(a: Int, b: Int): Int = a + b
fun greet(name: String): String = "Hello, $name"

fun main() {
    // Basic function reference
    val f = ::double
    println(f(5))

    // Multi-param function reference
    val g = ::add
    println(g(3, 4))

    // String function reference
    val h = ::greet
    println(h("World"))

    // Callable ref invoked directly
    println((::double)(10))

    // Callable ref passed to map
    val list = listOf(1, 2, 3)
    val doubled = list.map(::double)
    println(doubled)

    // Callable ref passed to filter
    fun isEven(n: Int): Boolean = n % 2 == 0
    val evens = list.filter(::isEven)
    println(evens)
}
