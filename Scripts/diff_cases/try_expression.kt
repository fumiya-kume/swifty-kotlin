fun safeParse(s: String): Int =
    try { s.toInt() }
    catch (e: NumberFormatException) { -1 }

fun safeParseWithFinally(s: String): Int =
    try { s.toInt() }
    finally { println("done") }

fun main() {
    println(safeParse("42"))
    println(safeParse("abc"))
    println(safeParseWithFinally("99"))
}
