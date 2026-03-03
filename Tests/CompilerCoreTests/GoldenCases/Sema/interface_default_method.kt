package golden.sema

interface Greeter {
    fun greet(): String = "Hello"
}

class FormalGreeter : Greeter {
    override fun greet(): String = "Good day"
}

class DefaultGreeter : Greeter

interface Animal {
    fun name(): String
    fun sound(): String = "..."
}

class Dog : Animal {
    override fun name(): String = "Dog"
}
