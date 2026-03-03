object Counter {
    var n = 0
    fun increment() { n++ }
}

fun main() {
    Counter.increment()
    Counter.increment()
    println(Counter.n)
}
