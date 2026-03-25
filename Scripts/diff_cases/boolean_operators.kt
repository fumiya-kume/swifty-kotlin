fun main() {
    println("=== Boolean Operators Test ===")
    
    // Basic boolean values
    val trueVal = true
    val falseVal = false
    
    // Logical NOT
    println("Logical NOT:")
    println(!trueVal)
    println(!falseVal)
    
    // Logical AND
    println("\nLogical AND:")
    println(trueVal and falseVal)
    println(trueVal and trueVal)
    println(falseVal and falseVal)
    println(falseVal and trueVal)
    
    // Logical OR
    println("\nLogical OR:")
    println(trueVal or falseVal)
    println(trueVal or trueVal)
    println(falseVal or falseVal)
    println(falseVal or trueVal)
    
    // Complex expressions
    println("\nComplex expressions:")
    println(trueVal and falseVal or trueVal)
    println(falseVal or trueVal and falseVal)
    println(!(trueVal and falseVal))
    println(!(falseVal or falseVal))
    
    // Truth table
    println("\nTruth table:")
    println("A B | AND | OR | NOT A")
    println("T T | ${true and true} | ${true or true} | ${!true}")
    println("T F | ${true and false} | ${true or false} | ${!true}")
    println("F T | ${false and true} | ${false or true} | ${!false}")
    println("F F | ${false and false} | ${false or false} | ${!false}")
}
