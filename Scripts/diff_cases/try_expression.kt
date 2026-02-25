fun tryCatchExpr(): String =
    try { "ok" }
    catch (e: Exception) { "error" }

fun tryFinallyExpr(): String =
    try { "result" }
    finally { println("cleanup") }

fun main() {
    println(tryCatchExpr())
    println(tryFinallyExpr())
}
