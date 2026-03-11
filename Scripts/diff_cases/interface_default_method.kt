interface Greeter {
    fun greet(): String = "Hello"
}

class DefaultGreeter : Greeter
class CustomGreeter : Greeter {
    override fun greet(): String = "Hi"
}

fun main() {
    println(DefaultGreeter().greet())
    println(CustomGreeter().greet())
}
