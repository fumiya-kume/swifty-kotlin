// SKIP-DIFF
fun greet(name: String): String = "Hello, $name!"

fun add(a: Int, b: Int): Int = a + b

fun factorial(n: Int): Int = if (n <= 1) 1 else n * factorial(n - 1)

println(greet("World"))
println(add(3, 4))
println(factorial(5))
println(factorial(6))
