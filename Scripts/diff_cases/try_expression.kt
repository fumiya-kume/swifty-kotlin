class Handled : Throwable()
class Unhandled : Throwable()

fun choose(flag: Boolean): String =
    try {
        if (flag) "ok" else "err"
    } finally {
        println("finally")
    }

fun multi(flag: Int): Any? =
    try {
        if (flag == 0) throw Handled()
        if (flag == 1) throw Unhandled()
        "ok"
    } catch (e: Handled) {
        "handled"
    } catch (e: Unhandled) {
        7
    }

fun partialCatchRethrow(flag: Boolean): Int {
    var x: Int
    try {
        if (flag) throw Handled() else throw Unhandled()
    } catch (e: Handled) {
        x = 7
    }
    return x
}

fun main() {
    // Keep runtime parity stable while compiling try-as-expression cases.
    println("try-case")
}
