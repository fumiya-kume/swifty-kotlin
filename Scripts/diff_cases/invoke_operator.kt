class Adder {
    operator fun invoke(x: Int): Int = x + 1
}

val globalAdder: Adder = Adder()

object Incrementer {
    operator fun invoke(x: Int): Int = x + 2
}

fun makeAdder(): Adder = Adder()

fun main() {
    println(globalAdder(3))
    println(Incrementer(3))
    println(makeAdder()(3))
}
