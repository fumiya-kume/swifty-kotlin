package golden.sema

class Producer<out T>(val value: T)

class Consumer<in T> {
    fun accept(value: T) {}
}

fun useVariance() {
    val p: Producer<Any> = Producer(42)
    val c: Consumer<Int> = Consumer<Number>()
}
