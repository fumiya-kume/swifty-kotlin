fun main() {
    val s = buildString {
        appendLine("hello")
        appendLine("world")
        append("!")
    }
    println(s)
}
// SKIP-DIFF: buildString appendLine parity pending
