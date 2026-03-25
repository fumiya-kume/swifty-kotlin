fun main() {
    println("=== Char Operations Test ===")
    
    // Basic char operations
    val charA = 'A'
    val charZ = 'Z'
    val char0 = '0'
    val char9 = '9'
    
    // Char plus string
    println("Char + string:")
    println(charA + "pple")
    println(char0 + "123")
    
    // Char rangeTo
    println("\nChar ranges:")
    println(charA.rangeTo('D'))  // Should produce "ABCD"
    println(char0.rangeTo('3'))  // Should produce "0123"
    
    // Unicode char operations
    val unicodeChar = 'α'
    println("\nUnicode char:")
    println(unicodeChar + " greek")
    println(unicodeChar.rangeTo('δ'))
    
    // Edge cases
    println("\nEdge cases:")
    val replacementChar = '\uFFFD'
    println(replacementChar + " invalid")
    
    // Empty range (when start > end)
    println("\nEmpty range:")
    println('Z'.rangeTo('A'))  // Should produce empty string
}
