fun main() {
    // Comprehensive lastOrNull tests for kotlinc behavior verification
    
    // Basic List tests
    println("=== Basic List Tests ===")
    
    // 1. Basic lastOrNull on non-empty list
    val nums = listOf(10, 20, 30)
    println(nums.lastOrNull())

    // 2. lastOrNull on single-element list
    val single = listOf(42)
    println(single.lastOrNull())

    // 3. lastOrNull on mutableListOf
    val mutable = mutableListOf(1, 2, 3)
    println(mutable.lastOrNull())

    // 4. lastOrNull on list of strings
    val strings = listOf("hello", "world")
    println(strings.lastOrNull())

    // 5. Chained: map then lastOrNull
    val result = listOf(1, 2, 3).map { it * 10 }.lastOrNull()
    println(result)

    // 6. Chained: filter then lastOrNull
    val filtered = listOf(1, 2, 3, 4, 5).filter { it > 3 }.lastOrNull()
    println(filtered)
    
    // Empty collection tests
    println("\n=== Empty Collection Tests ===")
    
    val emptyList = emptyList<Int>()
    println("emptyList.lastOrNull(): ${emptyList.lastOrNull()}")
    
    val emptyStringList = emptyList<String>()
    println("emptyStringList.lastOrNull(): ${emptyStringList.lastOrNull()}")
    
    // String tests
    println("\n=== String Tests ===")
    
    // Empty string
    val emptyString = ""
    println("emptyString.lastOrNull(): ${emptyString.lastOrNull()}")
    
    // Single character string
    val singleCharString = "a"
    println("singleCharString.lastOrNull(): ${singleCharString.lastOrNull()}")
    
    // Multi-character string
    val multiCharString = "hello"
    println("multiCharString.lastOrNull(): ${multiCharString.lastOrNull()}")
    
    // Unicode string
    val unicodeString = "hello🌟"
    println("unicodeString.lastOrNull(): ${unicodeString.lastOrNull()}")
    
    // Set tests
    println("\n=== Set Tests ===")
    
    val emptySet = emptySet<Int>()
    println("emptySet.lastOrNull(): ${emptySet.lastOrNull()}")
    
    val singleSet = setOf(42)
    println("singleSet.lastOrNull(): ${singleSet.lastOrNull()}")
    
    val multiSet = setOf(3, 1, 4, 1, 5, 9)
    println("multiSet.lastOrNull(): ${multiSet.lastOrNull()}")
    
    // Sequence tests
    println("\n=== Sequence Tests ===")
    
    val emptySequence = sequenceOf<Int>()
    println("emptySequence.lastOrNull(): ${emptySequence.lastOrNull()}")
    
    val singleSequence = sequenceOf(42)
    println("singleSequence.lastOrNull(): ${singleSequence.lastOrNull()}")
    
    val multiSequence = sequenceOf(1, 2, 3, 4, 5)
    println("multiSequence.lastOrNull(): ${multiSequence.lastOrNull()}")
    
    // Type-specific tests
    println("\n=== Type-Specific Tests ===")
    
    // Boolean list
    val booleanList = listOf(true, false, true)
    println("booleanList.lastOrNull(): ${booleanList.lastOrNull()}")
    
    // Double list
    val doubleList = listOf(1.5, 2.7, 3.14)
    println("doubleList.lastOrNull(): ${doubleList.lastOrNull()}")
    
    // Character list
    val charList = listOf('a', 'b', 'c')
    println("charList.lastOrNull(): ${charList.lastOrNull()}")
    
    // Nullable type tests
    println("\n=== Nullable Type Tests ===")
    
    val nullableList: List<Int?> = listOf(5, null, null)
    println("nullableList.lastOrNull(): ${nullableList.lastOrNull()}")
    
    val allNullList: List<Int?> = listOf(null, null, null)
    println("allNullList.lastOrNull(): ${allNullList.lastOrNull()}")
    
    // Advanced operations
    println("\n=== Advanced Operations ===")
    
    // reversed() then lastOrNull
    val reversedLast = listOf(1, 2, 3, 4, 5).reversed().lastOrNull()
    println("reversedLast: ${reversedLast}")
    
    // asReversed() then lastOrNull
    val asReversedLast = listOf(1, 2, 3, 4, 5).asReversed().lastOrNull()
    println("asReversedLast: ${asReversedLast}")
    
    // sorted() then lastOrNull
    val sortedLast = listOf(3, 1, 4, 1, 5).sorted().lastOrNull()
    println("sortedLast: ${sortedLast}")
    
    // distinct() then lastOrNull
    val distinctLast = listOf(1, 2, 2, 3, 3, 3).distinct().lastOrNull()
    println("distinctLast: ${distinctLast}")
    
    // Edge cases
    println("\n=== Edge Cases ===")
    
    // Large list
    val largeList = (1..1000).toList()
    println("largeList.lastOrNull(): ${largeList.lastOrNull()}")
    
    // List with special values
    val specialList = listOf(Int.MAX_VALUE, Int.MIN_VALUE, 0, -1)
    println("specialList.lastOrNull(): ${specialList.lastOrNull()}")
    
    // String with whitespace
    val whitespaceString = "   \t\n"
    println("whitespaceString.lastOrNull(): ${whitespaceString.lastOrNull()}")
    
    // String with special characters
    val specialString = "!@#$%^&*()"
    println("specialString.lastOrNull(): ${specialString.lastOrNull()}")
    
    // Mutable collection after modifications
    println("\n=== Mutable Collection Tests ===")
    
    val mutableList = mutableListOf(10, 20, 30)
    println("mutableList.lastOrNull(): ${mutableList.lastOrNull()}")
    
    mutableList.add(40)
    println("afterAdd.lastOrNull(): ${mutableList.lastOrNull()}")
    
    mutableList.removeAt(0)
    println("afterRemove.lastOrNull(): ${mutableList.lastOrNull()}")
    
    mutableList.clear()
    println("afterClear.lastOrNull(): ${mutableList.lastOrNull()}")
}
// SKIP-DIFF: lastOrNull parity pending
