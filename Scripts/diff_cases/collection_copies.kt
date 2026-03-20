fun main() {
    val sourceList = listOf(1, 2, 2)
    val copiedList = sourceList.toMutableList()
    copiedList.add(3)
    println(sourceList)
    println(copiedList)

    val copiedSet = sourceList.toSet()
    println(copiedSet)
    println(copiedSet.contains(2))

    val sourceMap = mapOf("a" to 1)
    val copiedMap = sourceMap.toMutableMap()
    copiedMap["b"] = 2
    println(sourceMap)
    println(copiedMap)

    // --- toSet() comprehensive tests ---

    // Duplicate removal
    val dupes = listOf(3, 1, 4, 1, 5, 9, 2, 6, 5, 3, 5)
    val dupesSet = dupes.toSet()
    println(dupesSet)
    println(dupesSet.size)

    // Empty list to set
    val emptySet = emptyList<Int>().toSet()
    println(emptySet)
    println(emptySet.isEmpty())
    println(emptySet.size)

    // Single element
    val singleSet = listOf(42).toSet()
    println(singleSet)
    println(singleSet.size)

    // String toSet
    val strSet = listOf("apple", "banana", "apple", "cherry", "banana").toSet()
    println(strSet)
    println(strSet.size)
    println(strSet.contains("apple"))
    println(strSet.contains("grape"))

    // Set to set (idempotent)
    val alreadySet = setOf(10, 20, 30)
    val setFromSet = alreadySet.toSet()
    println(setFromSet)
    println(setFromSet.size)

    // toMutableSet and modification
    val mutableSet = listOf(1, 2, 3, 2, 1).toMutableSet()
    mutableSet.add(4)
    mutableSet.add(2) // already present
    println(mutableSet)
    println(mutableSet.size)

    // Insertion order preserved (LinkedHashSet)
    val orderedSet = listOf(5, 3, 1, 4, 1, 5, 9).toSet()
    println(orderedSet)

    // Boolean/nullable-free contains checks
    val numSet = listOf(10, 20, 30, 40, 50).toSet()
    println(numSet.contains(30))
    println(numSet.contains(99))
}
