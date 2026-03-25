// Test case for STDLIB-532: Map?.orEmpty() extension

fun main() {
    // Test null map
    val nullMap: Map<String, Int>? = null
    val emptyFromNull = nullMap.orEmpty()
    println("nullMap.orEmpty(): $emptyFromNull")
    println("Size: ${emptyFromNull.size}")
    
    // Test non-null map
    val nonNullMap: Map<String, Int>? = mapOf("a" to 1, "b" to 2, "c" to 3)
    val kept = nonNullMap.orEmpty()
    println("nonNullMap.orEmpty(): $kept")
    println("Size: ${kept.size}")
    
    // Test empty map
    val emptyMap: Map<String, Int>? = mapOf()
    val emptyFromEmpty = emptyMap.orEmpty()
    println("emptyMap.orEmpty(): $emptyFromEmpty")
    println("Size: ${emptyFromEmpty.size}")
    
    // Test map with different types
    val stringMap: Map<String, String>? = mapOf("key1" to "value1", "key2" to "value2")
    val stringResult = stringMap.orEmpty()
    println("stringMap.orEmpty(): $stringResult")
    
    // Test chained operations
    val chainedResult = nullMap.orEmpty().plus("d" to 4)
    println("chainedResult: $chainedResult")
    
    println("All tests completed successfully!")
}
