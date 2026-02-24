sealed interface Expr
class Literal : Expr
class Add : Expr
class Multiply : Expr

fun eval(e: Expr): String {
    return when (e) {
        is Literal -> "literal"
        is Add -> "add"
        is Multiply -> "multiply"
    }
}
