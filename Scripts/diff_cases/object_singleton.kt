object Counter {
    var n = 0
    init {
        n = 1
    }
}

fun main() {
    println(Counter.n)
    Counter.n = 3
    println(Counter.n)
}
