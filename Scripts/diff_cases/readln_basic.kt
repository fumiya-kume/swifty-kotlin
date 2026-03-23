// readln() with EOF: throws ReadAfterEOFException when stdin is empty
// DIFF_STDIN_EOF
fun main() {
    try {
        val line = readln()
        println(line)
    } catch (e: RuntimeException) {
        println(e.message)
    }
}
