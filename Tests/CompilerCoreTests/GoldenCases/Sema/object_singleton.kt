package golden.sema

object Counter {
    val label: String = "counter"
    var n: Int = 0

    init {
        n = 1
    }

    fun increment() { n = n + 1 }
}

fun useCounter() {
    Counter.increment()
    Counter.increment()
}
