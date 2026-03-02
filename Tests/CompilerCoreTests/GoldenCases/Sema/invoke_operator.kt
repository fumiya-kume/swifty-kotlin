package golden.sema

class Adder {
    operator fun invoke(x: Int): Int = x + 1
}

val globalAdder: Adder = Adder()

object Incrementer {
    operator fun invoke(x: Int): Int = x + 2
}

fun makeAdder(): Adder = Adder()

fun main() {
    val adder = Adder()
    val localResult: Int = adder(5)
    val topLevelResult: Int = globalAdder(6)
    val objectResult: Int = Incrementer(7)
    val exprResult: Int = makeAdder()(8)
}
