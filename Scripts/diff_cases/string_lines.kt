private fun dumpLines(lines: List<String>) {
    println(lines.size)
    for (line in lines) {
        println("[$line]")
    }
    println("--")
}

fun main() {
    // Basic cases
    dumpLines("a\nb\nc".lines())
    dumpLines("hello".lines())
    dumpLines("".lines())
    dumpLines("a\n\nb".lines())

    // Trailing newline
    dumpLines("a\nb\n".lines())

    // \r\n (Windows line endings)
    dumpLines("a\r\nb\r\nc".lines())

    // Mixed line endings
    dumpLines("a\nb\r\nc\rd".lines())

    // Only newlines
    dumpLines("\n".lines())
    dumpLines("\n\n".lines())
    dumpLines("\r\n".lines())

    // Single char
    dumpLines("x".lines())

    // lines() size
    println("a\nb\nc".lines().size)

    // Edge cases for comprehensive testing
    // Multiple trailing newlines
    dumpLines("a\nb\n\n".lines())
    dumpLines("a\nb\n\r\n".lines())

    // Starting with newlines
    dumpLines("\na\nb".lines())
    dumpLines("\r\na\nb".lines())

    // Only carriage returns
    dumpLines("\r".lines())
    dumpLines("\r\r".lines())

    // Complex mixed patterns
    dumpLines("a\r\n\nb\r\nc\n\r".lines())

    // Whitespace handling
    dumpLines(" \n \t\n ".lines())

    // Unicode content with newlines
    dumpLines("こんにちは\n世界\n".lines())
}
