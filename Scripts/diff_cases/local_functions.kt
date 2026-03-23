fun main() {
    fun factorial(n: Int): Int = if (n <= 1) 1 else n * factorial(n - 1)
    println(factorial(5))
    var counter = 0
    fun increment() { counter++ }
    increment()
    increment()
    println(counter)
    fun outer(x: Int): Int {
        fun inner(y: Int) = x + y
        return inner(10)
    }
    println(outer(5))
}
