// Test STDLIB-GEN-054: Variance generics - covariance, contravariance, invariance

// Covariant (out) interface - Producer pattern
interface Producer<out T> {
    fun produce(): T
}

// Contravariant (in) interface - Consumer pattern
interface Consumer<in T> {
    fun consume(value: T)
}

// Invariant interface - Container (both in and out positions)
interface Container<T> {
    fun fetch(): T
    fun store(value: T)
}

// Covariant class
class StringProducer(val value: String) : Producer<String> {
    override fun produce(): String = value
}

// Contravariant class
class AnyPrinter : Consumer<Any> {
    override fun consume(value: Any) {
        println("consumed: $value")
    }
}

// Invariant class
class StringContainer(val initial: String) : Container<String> {
    override fun fetch(): String = initial
    override fun store(value: String) = println("stored: $value")
}

// Variance and inheritance: covariant parameter
fun printAnyProduced(producer: Producer<Any>) {
    println(producer.produce())
}

// Variance and inheritance: contravariant parameter
fun feedStringConsumer(consumer: Consumer<String>) {
    consumer.consume("hello from feeder")
}

fun main() {
    // Covariance: Producer<String> can be assigned to Producer<Any>
    val stringProducer: Producer<String> = StringProducer("variance test")
    val anyProducer: Producer<Any> = stringProducer
    printAnyProduced(anyProducer)

    // Contravariance: Consumer<Any> can be assigned to Consumer<String>
    val anyConsumer: Consumer<Any> = AnyPrinter()
    val stringConsumer: Consumer<String> = anyConsumer
    feedStringConsumer(stringConsumer)

    // Invariance: Container<String> used directly (cannot be widened to Container<Any>)
    val container: Container<String> = StringContainer("invariant value")
    container.store("new value")
    println(container.fetch())
}
