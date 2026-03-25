fun main() {
    // Test cases for firstOrNull comprehensive verification
    
    // List tests
    println("=== List Tests ===")
    
    // Empty list
    val emptyList = emptyList<Int>()
    println("emptyList.firstOrNull(): ${emptyList.firstOrNull()}")
    
    // Single element list
    val singleList = listOf(42)
    println("singleList.firstOrNull(): ${singleList.firstOrNull()}")
    
    // Multiple elements list
    val multiList = listOf(1, 2, 3, 4, 5)
    println("multiList.firstOrNull(): ${multiList.firstOrNull()}")
    
    // List with null elements (shouldn't affect firstOrNull)
    val listWithNulls = listOf(1, null, 3, null, 5)
    println("listWithNulls.firstOrNull(): ${listWithNulls.firstOrNull()}")
    
    // String list
    val stringList = listOf("apple", "banana", "cherry")
    println("stringList.firstOrNull(): ${stringList.firstOrNull()}")
    
    val emptyStringList = emptyList<String>()
    println("emptyStringList.firstOrNull(): ${emptyStringList.firstOrNull()}")
    
    // String tests
    println("\n=== String Tests ===")
    
    // Empty string
    val emptyString = ""
    println("emptyString.firstOrNull(): ${emptyString.firstOrNull()}")
    
    // Single character string
    val singleCharString = "a"
    println("singleCharString.firstOrNull(): ${singleCharString.firstOrNull()}")
    
    // Multi-character string
    val multiCharString = "hello"
    println("multiCharString.firstOrNull(): ${multiCharString.firstOrNull()}")
    
    // Unicode string
    val unicodeString = "🌟hello"
    println("unicodeString.firstOrNull(): ${unicodeString.firstOrNull()}")
    
    // Sequence tests
    println("\n=== Sequence Tests ===")
    
    // Empty sequence
    val emptySequence = sequenceOf<Int>()
    println("emptySequence.firstOrNull(): ${emptySequence.firstOrNull()}")
    
    // Single element sequence
    val singleSequence = sequenceOf(42)
    println("singleSequence.firstOrNull(): ${singleSequence.firstOrNull()}")
    
    // Multiple elements sequence
    val multiSequence = sequenceOf(1, 2, 3, 4, 5)
    println("multiSequence.firstOrNull(): ${multiSequence.firstOrNull()}")
    
    // Generated sequence
    val generatedSequence = generateSequence(1) { it + 1 }.take(5)
    println("generatedSequence.firstOrNull(): ${generatedSequence.firstOrNull()}")
    
    // Type-specific tests
    println("\n=== Type-Specific Tests ===")
    
    // Boolean list
    val booleanList = listOf(true, false, true)
    println("booleanList.firstOrNull(): ${booleanList.firstOrNull()}")
    
    // Double list
    val doubleList = listOf(1.5, 2.7, 3.14)
    println("doubleList.firstOrNull(): ${doubleList.firstOrNull()}")
    
    // Character list
    val charList = listOf('a', 'b', 'c')
    println("charList.firstOrNull(): ${charList.firstOrNull()}")
    
    // Array tests (converted to List)
    println("\n=== Array Tests ===")
    
    val intArray = arrayOf(1, 2, 3)
    println("intArray.toList().firstOrNull(): ${intArray.toList().firstOrNull()}")
    
    val emptyIntArray = arrayOf<Int>()
    println("emptyIntArray.toList().firstOrNull(): ${emptyIntArray.toList().firstOrNull()}")
    
    // Set tests
    println("\n=== Set Tests ===")
    
    val emptySet = emptySet<Int>()
    println("emptySet.firstOrNull(): ${emptySet.firstOrNull()}")
    
    val singleSet = setOf(42)
    println("singleSet.firstOrNull(): ${singleSet.firstOrNull()}")
    
    val multiSet = setOf(3, 1, 4, 1, 5, 9)
    println("multiSet.firstOrNull(): ${multiSet.firstOrNull()}")
    
    // MutableCollection tests
    println("\n=== MutableCollection Tests ===")
    
    val mutableList = mutableListOf(10, 20, 30)
    println("mutableList.firstOrNull(): ${mutableList.firstOrNull()}")
    
    mutableList.clear()
    println("emptyMutableList.firstOrNull(): ${mutableList.firstOrNull()}")
    
    // Nullable type tests
    println("\n=== Nullable Type Tests ===")
    
    val nullableList: List<Int?> = listOf(null, null, 5)
    println("nullableList.firstOrNull(): ${nullableList.firstOrNull()}")
    
    val allNullList: List<Int?> = listOf(null, null, null)
    println("allNullList.firstOrNull(): ${allNullList.firstOrNull()}")
    
    // Edge cases
    println("\n=== Edge Cases ===")
    
    // Large list
    val largeList = (1..1000).toList()
    println("largeList.firstOrNull(): ${largeList.firstOrNull()}")
    
    // List with special values
    val specialList = listOf(0, -1, Int.MAX_VALUE, Int.MIN_VALUE)
    println("specialList.firstOrNull(): ${specialList.firstOrNull()}")
    
    // String with whitespace
    val whitespaceString = "   \t\n"
    println("whitespaceString.firstOrNull(): ${whitespaceString.firstOrNull()}")
    
    // String with special characters
    val specialString = "!@#$%^&*()"
    println("specialString.firstOrNull(): ${specialString.firstOrNull()}")
}
