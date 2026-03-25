fun main() {
    // Comprehensive tests for asReversed() vs reversed() behavior differences
    
    // Basic behavior comparison
    println("=== Basic Behavior Comparison ===")
    
    // Basic reversed() returns a new list
    val list = listOf(1, 2, 3, 4, 5)
    val rev = list.reversed()
    println("original: $list")
    println("reversed(): $rev")
    println("same reference: ${list === rev}")

    // Basic asReversed() returns a reversed view
    val asRev = list.asReversed()
    println("asReversed(): $asRev")
    println("same reference: ${list === asRev}")

    // Mutable list - independent copy vs view
    println("\n=== Mutable List - Copy vs View ===")
    
    // reversed() on mutable list returns independent copy
    val mutable = mutableListOf(10, 20, 30)
    val mutableRev = mutable.reversed()
    println("before change - mutable: $mutable, reversed(): $mutableRev")
    mutable[0] = 99
    println("after change - mutable: $mutable, reversed(): $mutableRev")

    // asReversed() on mutable list reflects changes
    val mutable2 = mutableListOf(10, 20, 30)
    val view = mutable2.asReversed()
    println("before change - mutable2: $mutable2, asReversed(): $view")
    mutable2[0] = 99
    println("after index change - mutable2: $mutable2, asReversed(): $view")
    mutable2.add(40)
    println("after add - mutable2: $mutable2, asReversed(): $view")
    mutable2.removeAt(1)
    println("after remove - mutable2: $mutable2, asReversed(): $view")

    // Edge cases
    println("\n=== Edge Cases ===")
    
    // Single element
    val single = listOf(42)
    println("single.reversed(): ${single.reversed()}")
    println("single.asReversed(): ${single.asReversed()}")

    // Empty list
    val empty = emptyList<Int>()
    println("empty.reversed(): ${empty.reversed()}")
    println("empty.asReversed(): ${empty.asReversed()}")

    // String list
    val stringList = listOf("a", "b", "c")
    println("stringList.reversed(): ${stringList.reversed()}")
    println("stringList.asReversed(): ${stringList.asReversed()}")

    // Double reversed
    val doubleRev = listOf(1, 2, 3).reversed().reversed()
    val doubleAsRev = listOf(1, 2, 3).asReversed().asReversed()
    println("double reversed(): $doubleRev")
    println("double asReversed(): $doubleAsRev")

    // Operations on reversed collections
    println("\n=== Operations on Reversed Collections ===")
    
    // Size and indexing on reversed view
    val view2 = listOf(5, 10, 15).asReversed()
    println("view2.size: ${view2.size}")
    println("view2[0]: ${view2[0]}")
    println("view2[2]: ${view2[2]}")

    // Map operations
    val revMap = listOf(1, 2, 3).reversed().map { it * 2 }
    val asRevMap = listOf(1, 2, 3).asReversed().map { it * 2 }
    println("reversed().map(): $revMap")
    println("asReversed().map(): $asRevMap")

    // Filter operations
    val revFilter = listOf(1, 2, 3, 4, 5).reversed().filter { it > 3 }
    val asRevFilter = listOf(1, 2, 3, 4, 5).asReversed().filter { it > 3 }
    println("reversed().filter(): $revFilter")
    println("asReversed().filter(): $asRevFilter")

    // Performance characteristics test
    println("\n=== Performance Characteristics ===")
    
    // Multiple calls to reversed() create new lists
    val original = listOf(1, 2, 3, 4, 5)
    val rev1 = original.reversed()
    val rev2 = original.reversed()
    println("rev1 === rev2: ${rev1 === rev2}")
    println("rev1 == rev2: ${rev1 == rev2}")

    // Multiple calls to asReversed() return same view
    val asRev1 = original.asReversed()
    val asRev2 = original.asReversed()
    println("asRev1 === asRev2: ${asRev1 === asRev2}")
    println("asRev1 == asRev2: ${asRev1 == asRev2}")

    // Type preservation
    println("\n=== Type Preservation ===")
    
    // String operations
    val stringRev = "hello".reversed()
    val stringAsRev = "hello".asReversed()
    println("string.reversed(): $stringRev")
    println("string.asReversed(): $stringAsRev")

    // Mutable operations on view
    println("\n=== Mutable Operations on View ===")
    
    val mutable3 = mutableListOf(1, 2, 3, 4, 5)
    val view3 = mutable3.asReversed()
    
    println("before: mutable3=$mutable3, view=$view3")
    
    // Modify through view if possible
    try {
        view3[0] = 99
        println("after view[0]=99: mutable3=$mutable3, view=$view3")
    } catch (e: Exception) {
        println("view modification failed: ${e.message}")
    }
    
    // Modify original
    mutable3[4] = 88
    println("after mutable3[4]=88: mutable3=$mutable3, view=$view3")

    // Complex operations
    println("\n=== Complex Operations ===")
    
    // Chained operations
    val chainRev = listOf(1, 2, 3, 4, 5).reversed().reversed().asReversed()
    val chainAsRev = listOf(1, 2, 3, 4, 5).asReversed().reversed().asReversed()
    println("chain reversed(): $chainRev")
    println("chain asReversed(): $chainAsRev")

    // Sorting after reversing
    val sortAfterRev = listOf(3, 1, 4, 1, 5).reversed().sorted()
    val sortAfterAsRev = listOf(3, 1, 4, 1, 5).asReversed().sorted()
    println("reversed().sorted(): $sortAfterRev")
    println("asReversed().sorted(): $sortAfterAsRev")

    // Large collection test
    println("\n=== Large Collection Test ===")
    
    val largeList = (1..100).toList()
    val largeRev = largeList.reversed()
    val largeAsRev = largeList.asReversed()
    
    println("largeList.first(): ${largeList.first()}")
    println("largeRev.first(): ${largeRev.first()}")
    println("largeAsRev.first(): ${largeAsRev.first()}")
    println("largeList.last(): ${largeList.last()}")
    println("largeRev.last(): ${largeRev.last()}")
    println("largeAsRev.last(): ${largeAsRev.last()}")
}
