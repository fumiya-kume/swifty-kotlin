fun main() {
    // Edge cases for firstOrNull verification
    
    println("=== Type Variety Tests ===")
    
    // Boolean
    val boolList = listOf(true, false, true)
    val emptyBoolList = emptyList<Boolean>()
    println("boolList.firstOrNull(): ${boolList.firstOrNull()}")
    println("emptyBoolList.firstOrNull(): ${emptyBoolList.firstOrNull()}")
    
    // Double
    val doubleList = listOf(1.5, 2.7, 3.14)
    val emptyDoubleList = emptyList<Double>()
    println("doubleList.firstOrNull(): ${doubleList.firstOrNull()}")
    println("emptyDoubleList.firstOrNull(): ${emptyDoubleList.firstOrNull()}")
    
    // Character
    val charList = listOf('a', 'b', 'c')
    val emptyCharList = emptyList<Char>()
    println("charList.firstOrNull(): ${charList.firstOrNull()}")
    println("emptyCharList.firstOrNull(): ${emptyCharList.firstOrNull()}")
    
    // Long
    val longList = listOf(10000000000L, 20000000000L)
    val emptyLongList = emptyList<Long>()
    println("longList.firstOrNull(): ${longList.firstOrNull()}")
    println("emptyLongList.firstOrNull(): ${emptyLongList.firstOrNull()}")
    
    println("\n=== String Edge Cases ===")
    
    // Unicode characters
    val unicodeStr = "🌟hello"
    val emptyUnicodeStr = ""
    println("unicodeStr.firstOrNull(): ${unicodeStr.firstOrNull()}")
    println("emptyUnicodeStr.firstOrNull(): ${emptyUnicodeStr.firstOrNull()}")
    
    // Special characters
    val specialStr = "!@#$%"
    println("specialStr.firstOrNull(): ${specialStr.firstOrNull()}")
    
    // Numbers as strings
    val numberStr = "12345"
    println("numberStr.firstOrNull(): ${numberStr.firstOrNull()}")
    
    println("\n=== List with Different Types ===")
    
    // Mixed types in string list
    val stringNumberList = listOf("1", "2", "3")
    println("stringNumberList.firstOrNull(): ${stringNumberList.firstOrNull()}")
    
    // List whose first element is null; firstOrNull returns that null.
    val listWithNulls = listOf(null, null, 42, null)
    println("listWithNulls.firstOrNull(): ${listWithNulls.firstOrNull()}")
    
    val listWithOnlyNulls = listOf<Int?>(null, null, null)
    println("listWithOnlyNulls.firstOrNull(): ${listWithOnlyNulls.firstOrNull()}")
    
    println("\n=== Large Collections ===")
    
    // Large list
    val largeList = (1..1000).toList()
    println("largeList.firstOrNull(): ${largeList.firstOrNull()}")
    
    // Large string
    val largeString = "a".repeat(1000)
    println("largeString.firstOrNull(): ${largeString.firstOrNull()}")
}
