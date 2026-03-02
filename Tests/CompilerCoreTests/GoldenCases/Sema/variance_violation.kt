package golden.sema

class Producer<out T>(val item: T)

class Consumer<in T> {
    fun accept(item: T) {}
}

// Valid covariant/contravariant assignments
fun validVariance() {
    val p: Producer<Any> = Producer(42)       // out: Int → Any OK
    val c: Consumer<Int> = Consumer<Number>() // in: Number → Int OK
}

// Illegal: out T used in 'in' position (parameter)
class BadProducer<out T> {
    fun consume(item: T) {} // ERROR: Type parameter T is declared as 'out' but occurs in 'in' position
}

// Illegal: in T used in 'out' position (return type)
class BadConsumer<in T> {
    fun produce(): T? = null // ERROR: Type parameter T is declared as 'in' but occurs in 'out' position
}
