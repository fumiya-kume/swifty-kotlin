fun main() {
    // Multi-key sort using sortedWith with a two-level comparator lambda
    val names = listOf("Charlie", "Alice", "Bob")
    val sorted = names.sortedWith { a, b ->
        val cmp = a.length - b.length
        if (cmp != 0) cmp else a.compareTo(b)
    }
    sorted.forEach { println(it) }
}
