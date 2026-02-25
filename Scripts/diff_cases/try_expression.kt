fun tryCatchExpr(): String =
    try { "ok" }
    catch (e: Exception) { "error" }

fun main() {
    println(tryCatchExpr())
}
