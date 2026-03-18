fun main() {
    // Multi-key ascending sort (equivalent to thenBy)
    val words = listOf("banana", "apple", "ant", "cherry", "avocado")
    println("-- thenBy (length then alpha) --")
    val sorted = words.sortedWith { a, b ->
        val lenCmp = a.length - b.length
        if (lenCmp != 0) lenCmp else a.compareTo(b)
    }
    println(sorted)
    // Multi-key with second key descending (equivalent to thenByDescending)
    println("-- thenByDescending (length asc, alpha desc) --")
    val sortedDesc = words.sortedWith { a, b ->
        val lenCmp = a.length - b.length
        if (lenCmp != 0) lenCmp else b.compareTo(a)
    }
    println(sortedDesc)
    // Simple descending sort
    println("-- descending --")
    println(listOf(3, 1, 4, 1, 5).sortedWith { a, b -> b - a })
}
