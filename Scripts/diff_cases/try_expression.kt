fun choose(flag: Boolean): String =
    try { if (flag) "ok" else "err" }
    finally { println("finally") }

fun main() {
    // Keep the runtime stable while still compiling try-as-expression + finally.
    println("try-case")
}
