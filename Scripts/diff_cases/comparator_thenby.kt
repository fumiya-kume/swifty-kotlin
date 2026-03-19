fun main() {
    // sortedBy on strings: sort by length ascending
    println("-- sortedBy length --")
    val words = listOf("cherry", "fig", "apple", "date", "banana")
    val byLen = words.sortedBy { it.length }
    for (w in byLen) {
        println(w)
    }

    // sortedBy on strings: sort by natural order
    println("-- sortedBy natural --")
    val byAlpha = words.sortedBy { it }
    for (w in byAlpha) {
        println(w)
    }

    // sortedWith on integers: ascending
    println("-- ascending --")
    println(listOf(3, 1, 4, 1, 5).sortedWith { a, b -> a - b })

    // sortedWith on integers: descending
    println("-- descending --")
    println(listOf(3, 1, 4, 1, 5).sortedWith { a, b -> b - a })

    // sortedByDescending on integers
    println("-- sortedByDescending --")
    println(listOf(3, 1, 4, 1, 5).sortedByDescending { it })
}
