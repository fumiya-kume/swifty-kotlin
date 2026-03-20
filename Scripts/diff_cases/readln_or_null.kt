// readlnOrNull() returns null when stdin is at EOF
// DIFF_STDIN_EOF
fun main() {
    val line: String? = readlnOrNull()
    println(line)
}
