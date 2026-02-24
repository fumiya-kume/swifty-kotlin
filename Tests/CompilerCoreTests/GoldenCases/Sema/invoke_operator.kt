package golden.sema

class Adder(val base: Int) {
    operator fun invoke(x: Int): Int = base + x
}

fun main() {
    val adder = Adder(10)
    val result: Int = adder(5)
}
