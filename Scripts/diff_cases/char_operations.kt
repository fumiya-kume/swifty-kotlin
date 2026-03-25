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
    
    // New numeric conversion functions
    println("\n=== Numeric Conversion Tests ===")
    println("charA.toInt(): ${charA.toInt()}")  // Should return 65 (Unicode code point)
    println("charA.toDouble(): ${charA.toDouble()}")  // Should return 65.0
    println("char0.toIntOrNull(): ${char0.toIntOrNull()}")  // Should return 0
    println("char9.toIntOrNull(): ${char9.toIntOrNull()}")  // Should return 9
    println("charA.toIntOrNull(): ${charA.toIntOrNull()}")  // Should return null
    println("char0.toDoubleOrNull(): ${char0.toDoubleOrNull()}")  // Should return 0.0
    println("charA.toDoubleOrNull(): ${charA.toDoubleOrNull()}")  // Should return null
    
    // Code point and Unicode properties
    println("\n=== Unicode Properties Tests ===")
    println("charA.code: ${charA.code}")  // Should return 65
    println("char0.code: ${char0.code}")  // Should return 48
    println("unicodeChar.code: ${unicodeChar.code}")  // Should return 945
    
    println("charA.category: ${charA.category}")  // Should be UPPERCASE_LETTER
    println("char0.category: ${char0.category}")  // Should be DECIMAL_DIGIT_NUMBER
    println("unicodeChar.category: ${unicodeChar.category}")  // Should be LOWERCASE_LETTER
    
    println("charA.directionality: ${charA.directionality}")  // Should be LEFT_TO_RIGHT
    println("unicodeChar.directionality: ${unicodeChar.directionality}")  // Should be LEFT_TO_RIGHT
    
    // Test with RTL character (Arabic)
    val rtlChar = 'ا'  // Arabic letter
    println("\nRTL Character Test:")
    println("rtlChar.code: ${rtlChar.code}")
    println("rtlChar.category: ${rtlChar.category}")
    println("rtlChar.directionality: ${rtlChar.directionality}")  // Should be RIGHT_TO_LEFT
}
// SKIP-DIFF: Char operation parity pending
