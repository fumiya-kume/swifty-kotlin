private fun dumpLines(lines: List<String>) {
    println(lines.size)
    for (line in lines) {
        println("[$line]")
    }
    println("--")
}

fun main() {
    // Basic cases
    dumpLines("a\nb\nc".lineSequence().toList())
    dumpLines("a\nb\nc".lines())

    dumpLines("hello".lineSequence().toList())
    dumpLines("hello".lines())

    dumpLines("".lineSequence().toList())
    dumpLines("".lines())

    dumpLines("a\n\nb".lineSequence().toList())
    dumpLines("a\n\nb".lines())

    // Trailing newline
    dumpLines("a\nb\n".lineSequence().toList())
    dumpLines("a\nb\n".lines())

    // \r\n (Windows line endings)
    dumpLines("a\r\nb\r\nc".lineSequence().toList())
    dumpLines("a\r\nb\r\nc".lines())

    // Mixed line endings
    dumpLines("a\nb\r\nc\rd".lineSequence().toList())
    dumpLines("a\nb\r\nc\rd".lines())

    // Only newlines
    dumpLines("\n".lineSequence().toList())
    dumpLines("\n".lines())

    dumpLines("\n\n".lineSequence().toList())
    dumpLines("\n\n".lines())

    dumpLines("\r\n".lineSequence().toList())
    dumpLines("\r\n".lines())

    // Single char
    dumpLines("x".lineSequence().toList())
    dumpLines("x".lines())

    // lineSequence() size
    println("a\nb\nc".lineSequence().toList().size)

    // Edge cases for comprehensive testing
    // Multiple trailing newlines
    dumpLines("a\nb\n\n".lineSequence().toList())
    dumpLines("a\nb\n\n".lines())

    dumpLines("a\nb\n\r\n".lineSequence().toList())
    dumpLines("a\nb\n\r\n".lines())

    // Starting with newlines
    dumpLines("\na\nb".lineSequence().toList())
    dumpLines("\na\nb".lines())

    dumpLines("\r\na\nb".lineSequence().toList())
    dumpLines("\r\na\nb".lines())

    // Only carriage returns
    dumpLines("\r".lineSequence().toList())
    dumpLines("\r".lines())

    dumpLines("\r\r".lineSequence().toList())
    dumpLines("\r\r".lines())

    // Complex mixed patterns
    dumpLines("a\r\n\nb\r\nc\n\r".lineSequence().toList())
    dumpLines("a\r\n\nb\r\nc\n\r".lines())

    // Whitespace handling
    dumpLines(" \n \t\n ".lineSequence().toList())
    dumpLines(" \n \t\n ".lines())

    // Unicode content with newlines
    dumpLines("こんにちは\n世界\n".lineSequence().toList())
    dumpLines("こんにちは\n世界\n".lines())
}
