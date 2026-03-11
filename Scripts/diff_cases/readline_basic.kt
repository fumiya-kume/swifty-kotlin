// readLine() with EOF: when run with </dev/null, returns null and prints "null"
// DIFF_STDIN_EOF
fun main() {
    val line = readLine()
    println(line)
}
