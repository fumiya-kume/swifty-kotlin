class Greeter(val prefix: String) {
    fun greet(name: String): String = "$prefix $name"
}

fun main() {
    val greeter = Greeter("Hello")

    // Bound member reference
    val bound = greeter::greet
    println(bound("World"))

    // Function reference used with HOF
    fun double(x: Int): Int = x * 2
    val nums = listOf(1, 2, 3)
    println(nums.map(::double))

    // Function reference identity: name
    val f = ::double
    println(f(10))
}
