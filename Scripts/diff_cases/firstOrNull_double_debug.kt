fun main() {
    println("=== Double Debug Test ===")
    
    val doubleList = listOf(1.5, 2.7, 3.14)
    println("doubleList: $doubleList")
    println("doubleList[0]: ${doubleList[0]}")
    println("doubleList.firstOrNull(): ${doubleList.firstOrNull()}")
    
    // Test with different double values
    val singleDouble = listOf(42.0)
    println("singleDouble.firstOrNull(): ${singleDouble.firstOrNull()}")
    
    // Test with zero
    val zeroDouble = listOf(0.0)
    println("zeroDouble.firstOrNull(): ${zeroDouble.firstOrNull()}")
    
    // Test with negative
    val negDouble = listOf(-1.5)
    println("negDouble.firstOrNull(): ${negDouble.firstOrNull()}")
}
// SKIP-DIFF: firstOrNull parity pending
