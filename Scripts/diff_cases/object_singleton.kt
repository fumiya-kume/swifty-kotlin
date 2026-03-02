object Counter {
    var n: Int = 0
    fun increment() { n = n + 1 }
}

fun main() {
    Counter.increment()
    Counter.increment()
    println(Counter.n)
}
