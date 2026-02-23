package golden.sema

interface Greeter {
    fun greet(): String = "Hello"
}

class FormalGreeter : Greeter {
    override fun greet(): String = "Good day"
}

class DefaultGreeter : Greeter
