fun main() {
    // Existing bitwise operators
    println("=== Bitwise Operators (Int) ===")
    println(255 and 15)
    println(240 or 15)
    println(255 xor 15)
    println(255.inv())
    println(1 shl 3)
    println(16 shr 2)
    println(16 ushr 2)
    println((255 and 15).toString(16))
    println(255.toString(16))
    println(1.toString(2))
    
    // Bitwise operators with Long
    println("=== Bitwise Operators (Long) ===")
    val longA = 255L
    val longB = 15L
    println(longA and longB)
    println(longA or longB)
    println(longA xor longB)
    println(longA.inv())
    println(1L shl 3)
    println(16L shr 2)
    println(16L ushr 2)
    
    // Arithmetic operators (Int)
    println("=== Arithmetic Operators (Int) ===")
    println(5 + 3)
    println(5 - 3)
    println(5 * 3)
    println(10 / 3)
    println(10 % 3)
    println(-10 % 3)
    println(10 % -3)
    
    // Arithmetic operators (Long)
    println("=== Arithmetic Operators (Long) ===")
    println(5L + 3L)
    println(5L - 3L)
    println(5L * 3L)
    println(10L / 3L)
    println(10L % 3L)
    
    // Arithmetic operators (Double)
    println("=== Arithmetic Operators (Double) ===")
    println(5.5 + 3.2)
    println(5.5 - 3.2)
    println(5.5 * 3.2)
    println(10.0 / 3.0)
    println(10.5 % 3.2)
    
    // Arithmetic operators (Float)
    println("=== Arithmetic Operators (Float) ===")
    println(5.5f + 3.2f)
    println(5.5f - 3.2f)
    println(5.5f * 3.2f)
    println(10.0f / 3.0f)
    println(10.5f % 3.2f)
    
    // Comparison operators
    println("=== Comparison Operators ===")
    println(5 == 3)
    println(5 != 3)
    println(5 < 3)
    println(5 <= 3)
    println(5 > 3)
    println(5 >= 3)
    
    // Comparison with different types
    println("=== Comparison Operators (Mixed Types) ===")
    println(5 == 5L)
    println(5.0 == 5)
    println(5.5f < 6.0)
    
    // Boolean logical operators
    println("=== Boolean Logical Operators ===")
    println(true and false)
    println(true or false)
    println(!true)
    println(!false)
    println(true and true)
    println(false or false)
    println(true or true)
    println(false and false)
    
    // Char operations
    println("=== Char Operations ===")
    val charA = 'A'
    val charB = 'B'
    println(charA + " test")
    println(charA.rangeTo('D'))
    println(charA < charB)
    println(charA <= charB)
    println(charA > charB)
    println(charA >= charB)
    println(charA == charB)
    println(charA != charB)
    
    // Char get operation (if supported)
    println("=== Char Get Operation ===")
    try {
        println(charA.get(0))
    } catch (e: Exception) {
        println("Char.get not supported: ${e.message}")
    }
    
    // Additional edge cases
    println("=== Edge Cases ===")
    println(0 and 0)
    println(0 or 0)
    println(0 xor 0)
    println(Int.MAX_VALUE + 1)
    println(Int.MIN_VALUE - 1)
    println(0 / 1)
    // println(1 / 0) // Would throw exception - commented out for testing
}
// SKIP-DIFF: bitwise operator parity pending
