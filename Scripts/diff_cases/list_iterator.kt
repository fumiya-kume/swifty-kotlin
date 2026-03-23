fun main() {
    val list = listOf(10, 20, 30)
    val iter = list.listIterator()

    // Forward traversal
    while (iter.hasNext()) {
        print("${iter.next()} ")
    }
    println()

    // Backward traversal
    while (iter.hasPrevious()) {
        print("${iter.previous()} ")
    }
    println()
}
