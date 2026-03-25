fun main() {
    // Basic cases
    println("a\nb\nc".lineSequence().toList())
    println("a\nb\nc".lines())
    
    println("hello".lineSequence().toList())
    println("hello".lines())
    
    println("".lineSequence().toList())
    println("".lines())
    
    println("a\n\nb".lineSequence().toList())
    println("a\n\nb".lines())

    // Trailing newline
    println("a\nb\n".lineSequence().toList())
    println("a\nb\n".lines())

    // \r\n (Windows line endings)
    println("a\r\nb\r\nc".lineSequence().toList())
    println("a\r\nb\r\nc".lines())

    // Mixed line endings
    println("a\nb\r\nc\rd".lineSequence().toList())
    println("a\nb\r\nc\rd".lines())

    // Only newlines
    println("\n".lineSequence().toList())
    println("\n".lines())
    
    println("\n\n".lineSequence().toList())
    println("\n\n".lines())
    
    println("\r\n".lineSequence().toList())
    println("\r\n".lines())

    // Single char
    println("x".lineSequence().toList())
    println("x".lines())

    // lineSequence() size
    println("a\nb\nc".lineSequence().toList().size)

    // Edge cases for comprehensive testing
    // Multiple trailing newlines
    println("a\nb\n\n".lineSequence().toList())
    println("a\nb\n\n".lines())
    
    println("a\nb\n\r\n".lineSequence().toList())
    println("a\nb\n\r\n".lines())
    
    // Starting with newlines
    println("\na\nb".lineSequence().toList())
    println("\na\nb".lines())
    
    println("\r\na\nb".lineSequence().toList())
    println("\r\na\nb".lines())
    
    // Only carriage returns
    println("\r".lineSequence().toList())
    println("\r".lines())
    
    println("\r\r".lineSequence().toList())
    println("\r\r".lines())
    
    // Complex mixed patterns
    println("a\r\n\nb\r\nc\n\r".lineSequence().toList())
    println("a\r\n\nb\r\nc\n\r".lines())
    
    // Whitespace handling
    println(" \n \t\n ".lineSequence().toList())
    println(" \n \t\n ".lines())
    
    // Unicode content with newlines
    println("こんにちは\n世界\n".lineSequence().toList())
    println("こんにちは\n世界\n".lines())
}
