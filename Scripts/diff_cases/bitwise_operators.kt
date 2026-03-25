fun main() {
    // Existing bitwise operators
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
    
    // New comparison operators
    println("=== Comparison Operators ===")
    println(5 == 3)
    println(5 != 3)
    println(5 < 3)
    println(5 <= 3)
    println(5 > 3)
    println(5 >= 3)
    
    // New modulo operators
    println("=== Modulo Operators ===")
    println(10 % 3)
    println(-10 % 3)
    println(10 % -3)
    
    // Boolean logical operators
    println("=== Boolean Logical Operators ===")
    println(true and false)
    println(true or false)
    println(!true)
    println(!false)
    
    // Char operations
    println("=== Char Operations ===")
    val charA = 'A'
    println(charA + " test")
    println(charA.rangeTo('D'))
}
// SKIP-DIFF: bitwise operator parity pending
