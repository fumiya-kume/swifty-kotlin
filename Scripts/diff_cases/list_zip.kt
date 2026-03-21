fun main() {
    // Basic zip
    val a = listOf(1, 2, 3)
    val b = listOf("a", "b", "c")
    println(a.zip(b))

    // Different lengths (shorter truncates)
    val short = listOf(1, 2)
    val long = listOf("x", "y", "z", "w")
    println(short.zip(long))
    println(long.zip(short))

    // Single element zip
    println(listOf(42).zip(listOf("hello")))

    // Pair access
    val pairs = listOf(1, 2, 3).zip(listOf("a", "b", "c"))
    for (p in pairs) {
        println("${p.first} -> ${p.second}")
    }
}
