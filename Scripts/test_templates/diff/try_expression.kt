fun safeParse(s: String): Int =
    try { s.toInt() }
    catch (e: NumberFormatException) { -1 }

fun main() {
    println(safeParse("42"))
    println(safeParse("abc"))
}
