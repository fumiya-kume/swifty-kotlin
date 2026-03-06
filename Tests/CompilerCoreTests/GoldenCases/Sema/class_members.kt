package golden.sema

class Counter(initial0: Int) {
    val initial: Int = initial0
    var count: Int = initial
    val label: String = "counter"

    fun increment() {
        count = count + 1
    }

    fun get(): Int = count
}

object Singleton {
    val name: String = "singleton"
    fun greet(): String = "hello"
}
