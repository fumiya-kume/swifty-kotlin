interface Greeter {
    fun greet(): Int
}

class FormalGreeter : Greeter {
    override fun greet(): Int = 10
}

class CasualGreeter : Greeter {
    override fun greet(): Int = 20
}

fun performGreet(g: Greeter): Int = g.greet()

fun main() {
    val formal = FormalGreeter()
    val casual = CasualGreeter()
    println(performGreet(formal))
    println(performGreet(casual))
}
