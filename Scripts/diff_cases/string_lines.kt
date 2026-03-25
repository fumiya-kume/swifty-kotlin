fun main() {
    // Basic cases
    println("a\nb\nc".lines())
    println("hello".lines())
    println("".lines())
    println("a\n\nb".lines())

    // Trailing newline
    println("a\nb\n".lines())

    // \r\n (Windows line endings)
    println("a\r\nb\r\nc".lines())

    // Mixed line endings
    println("a\nb\r\nc\rd".lines())

    // Only newlines
    println("\n".lines())
    println("\n\n".lines())
    println("\r\n".lines())

    // Single char
    println("x".lines())

    // lines() size
    println("a\nb\nc".lines().size)

    // Edge cases for comprehensive testing
    // Multiple trailing newlines
    println("a\nb\n\n".lines())
    println("a\nb\n\r\n".lines())
    
    // Starting with newlines
    println("\na\nb".lines())
    println("\r\na\nb".lines())
    
    // Only carriage returns
    println("\r".lines())
    println("\r\r".lines())
    
    // Complex mixed patterns
    println("a\r\n\nb\r\nc\n\r".lines())
    
    // Whitespace handling
    println(" \n \t\n ".lines())
    
    // Unicode content with newlines
    println("こんにちは\n世界\n".lines())
}
