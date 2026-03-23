fun main() {
    // toMutableList() from List
    val sourceList = listOf(1, 2, 3)
    val copiedList = sourceList.toMutableList()
    copiedList.add(4)
    println(sourceList)
    println(copiedList)

    // toMutableList() returns independent copy
    val original = listOf("a", "b", "c")
    val mutable = original.toMutableList()
    mutable[0] = "z"
    mutable.add("d")
    println(original)
    println(mutable)

    // toMutableList() from MutableList (creates a copy)
    val mutableOrig = mutableListOf(1, 2, 3)
    val mutableCopy = mutableOrig.toMutableList()
    mutableCopy.add(4)
    mutableOrig.add(5)
    println(mutableOrig)
    println(mutableCopy)

    // toMutableList() preserves order
    val ordered = listOf(5, 3, 1, 4, 2)
    val orderedMutable = ordered.toMutableList()
    println(orderedMutable)

    // Chaining: toMutableList then sort
    val unsorted = listOf(3, 1, 4, 1, 5)
    val sorted = unsorted.toMutableList()
    sorted.sort()
    println(unsorted)
    println(sorted)

    // Multiple toMutableList() calls create independent copies
    val base = listOf(1, 2, 3)
    val copy1 = base.toMutableList()
    val copy2 = base.toMutableList()
    copy1.add(10)
    copy2.add(20)
    println(base)
    println(copy1)
    println(copy2)

    // toSet() with duplicate removal
    val dupes = listOf(3, 1, 4, 1, 5, 9, 2, 6, 5, 3, 5)
    val dupesSet = dupes.toSet()
    println(dupesSet)
    println(dupesSet.size)

    // String toSet
    val strSet = listOf("apple", "banana", "apple", "cherry", "banana").toSet()
    println(strSet)
    println(strSet.size)
    println(strSet.contains("apple"))
    println(strSet.contains("grape"))

    // toMutableSet and modification
    val mutableSet = listOf(1, 2, 3, 2, 1).toMutableSet()
    mutableSet.add(4)
    mutableSet.add(2)
    println(mutableSet)
    println(mutableSet.size)
}
