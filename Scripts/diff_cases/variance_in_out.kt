class Producer<out T>(private val value: T) { fun get(): T = value }
class Consumer<in T> { fun accept(value: T) = println("accepted: $value") }
fun main() {
    val stringProducer: Producer<String> = Producer("hello")
    val anyProducer: Producer<Any> = stringProducer
    println(anyProducer.get())
    val anyConsumer: Consumer<Any> = Consumer()
    val stringConsumer: Consumer<String> = anyConsumer
    stringConsumer.accept("world")
}
