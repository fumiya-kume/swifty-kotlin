fun main() {
    // Comprehensive binarySearch(compare) overload tests
    
    println("=== Basic binarySearch with comparison function ===")
    
    val list = listOf(1, 5, 10, 15, 20, 25, 30)

    // Find element 15 using comparison lambda
    val idx = list.binarySearch { it - 15 }
    println("find 15: $idx") // 3

    // Element not found (between 10 and 15)
    val missing = list.binarySearch { it - 12 }
    println("find 12 (missing): $missing") // negative (insertion point encoded)

    // First element
    val first = list.binarySearch { it - 1 }
    println("find 1: $first") // 0

    // Last element
    val last = list.binarySearch { it - 30 }
    println("find 30: $last") // 6

    // Element smaller than all
    val tooSmall = list.binarySearch { it - (-1) }
    println("find -1: $tooSmall") // negative

    // Element larger than all
    val tooLarge = list.binarySearch { it - 100 }
    println("find 100: $tooLarge") // negative
    
    println("\n=== Comparison function variations ===")
    
    // Using different comparison strategies
    val reverseCompare = list.binarySearch { 15 - it }
    println("reverse compare for 15: $reverseCompare")
    
    // Using when expression
    val whenCompare = list.binarySearch {
        when {
            it < 15 -> -1
            it > 15 -> 1
            else -> 0
        }
    }
    println("when compare for 15: $whenCompare")
    
    // Using compareTo
    val compareToResult = list.binarySearch { it.compareTo(20) }
    println("compareTo for 20: $compareToResult")
    
    println("\n=== Different data types ===")
    
    // String list
    val stringList = listOf("apple", "banana", "cherry", "date", "elderberry")
    val stringSearch = stringList.binarySearch { it.compareTo("cherry") }
    println("string search 'cherry': $stringSearch")
    
    val missingString = stringList.binarySearch { it.compareTo("blueberry") }
    println("string search 'blueberry' (missing): $missingString")
    
    // Double list
    val doubleList = listOf(1.1, 2.2, 3.3, 4.4, 5.5)
    val doubleSearch = doubleList.binarySearch { it.compareTo(3.3) }
    println("double search 3.3: $doubleSearch")
    
    println("\n=== Complex comparison logic ===")
    
    // Custom object comparison
    data class Person(val name: String, val age: Int)
    
    val people = listOf(
        Person("Alice", 25),
        Person("Bob", 30),
        Person("Charlie", 35),
        Person("David", 40)
    )
    
    // Search by age
    val ageSearch = people.binarySearch { it.age.compareTo(35) }
    println("search age 35: $ageSearch")
    
    // Search by name
    val nameSearch = people.binarySearch { it.name.compareTo("Bob") }
    println("search name 'Bob': $nameSearch")
    
    println("\n=== Edge cases ===")
    
    // Empty list
    val emptyList = emptyList<Int>()
    val emptySearch = emptyList.binarySearch { it.compareTo(5) }
    println("empty list search: $emptySearch")
    
    // Single element list
    val singleList = listOf(42)
    val singleFound = singleList.binarySearch { it.compareTo(42) }
    val singleMissing = singleList.binarySearch { it.compareTo(100) }
    println("single element found: $singleFound")
    println("single element missing: $singleMissing")
    
    // Large list
    val largeList = (1..1000).toList()
    val largeSearch = largeList.binarySearch { it.compareTo(500) }
    println("large list search 500: $largeSearch")
    
    println("\n=== Comparison function edge cases ===")
    
    // Comparison function that returns non-standard values
    val weirdCompare = list.binarySearch { 
        when {
            it < 15 -> -5
            it > 15 -> 10
            else -> 0
        }
    }
    println("weird compare values: $weirdCompare")
    
    // Always negative comparison
    val alwaysNegative = list.binarySearch { -1 }
    println("always negative: $alwaysNegative")
    
    // Always positive comparison
    val alwaysPositive = list.binarySearch { 1 }
    println("always positive: $alwaysPositive")
    
    println("\n=== Performance and behavior verification ===")
    
    // Verify insertion point encoding for missing elements
    val testList = listOf(10, 20, 30, 40, 50)
    
    // Search for values that should go at various positions
    val beforeFirst = testList.binarySearch { it.compareTo(5) }   // Should be -1
    val between1 = testList.binarySearch { it.compareTo(25) }    // Should be -3
    val between2 = testList.binarySearch { it.compareTo(35) }    // Should be -4
    val afterLast = testList.binarySearch { it.compareTo(60) }    // Should be -6
    
    println("before first (5): $beforeFirst")
    println("between 20-30 (25): $between1")
    println("between 30-40 (35): $between2")
    println("after last (60): $afterLast")
    
    // Verify the insertion point formula: -(insertion point) - 1
    println("insertion point for 25: ${-between1 - 1}")
    println("insertion point for 35: ${-between2 - 1}")
    
    println("\n=== Type safety tests ===")
    
    // Generic types
    val genericList: List<Comparable<Any>> = listOf(1, 2, 3, 4, 5)
    val genericSearch = genericList.binarySearch { (it as Int).compareTo(3) }
    println("generic search: $genericSearch")
    
    // Mixed types with custom comparison
    val mixedList = listOf("1", "2", "3", "4", "5")
    val mixedSearch = mixedList.binarySearch { it.toInt().compareTo(3) }
    println("mixed type search: $mixedSearch")
}
