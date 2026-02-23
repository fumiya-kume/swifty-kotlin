package golden.sema

object Counter {
    var n: Int = 0
    fun increment() { n = n + 1 }
}

fun useCounter() {
    Counter.increment()
    Counter.increment()
}
