// KSP-1285: IntRange members retain priority over user extensions, while
// exact cross-type user extensions win over the bundled source overloads.
operator fun IntRange.contains(value: Int): Boolean {
    println("extension-int")
    return false
}

operator fun IntRange.contains(value: String): Boolean {
    println("extension-string")
    return false
}

operator fun IntRange.contains(value: Long): Boolean {
    println("extension-long")
    return false
}

fun main() {
    val range: IntRange = 1..3
    println(range.contains(2))
    println(2 in range)
    println(range.contains(2L))
    println(2L in range)
}
