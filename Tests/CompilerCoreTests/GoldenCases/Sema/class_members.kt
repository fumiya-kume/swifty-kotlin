package golden.sema

class Counter(val initial: Int) {
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
