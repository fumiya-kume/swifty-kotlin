// readLine() with EOF: when run with </dev/null, returns null
// DIFF_STDIN_EOF
fun main() {
    // Basic readLine() returns null on EOF
    val line = readLine()
    println(line)

    // readLine() is nullable – null check works
    val line2 = readLine()
    if (line2 == null) {
        println("EOF reached")
    } else {
        println("got: $line2")
    }

    // Elvis operator with readLine()
    val line3 = readLine() ?: "default"
    println(line3)

    // Multiple readLine() calls all return null on EOF
    val results = listOf(readLine(), readLine(), readLine())
    println(results)
}
