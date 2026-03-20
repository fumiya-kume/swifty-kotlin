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
}
