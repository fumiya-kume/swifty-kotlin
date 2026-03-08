sealed interface Expr

class Num(val n: Int) : Expr

fun eval(e: Expr): Int = when (e) {
    is Num -> e.n
}

fun main() {
    println(eval(Num(7)))
}
