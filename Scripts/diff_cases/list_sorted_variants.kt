fun main() {
    val list = listOf(3, 1, 4, 1, 5, 9, 2, 6)

    // sortedDescending
    println(list.sortedDescending())

    // sortedByDescending
    println(list.sortedByDescending { it })

    // sortedWith
    println(list.sortedWith { a, b -> a - b })
    println(list.sortedWith { a, b -> b - a })
}
