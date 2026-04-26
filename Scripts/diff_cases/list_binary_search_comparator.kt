fun main() {
    val ascending = listOf(1, 3, 5, 7, 9)
    val descending = listOf(9, 7, 5, 3, 1)

    val natural = naturalOrder<Int>()
    val reversed = reverseOrder<Int>()

    println("=== binarySearch(element, comparator, fromIndex, toIndex) ===")
    println(ascending.binarySearch(5, natural))
    println(ascending.binarySearch(6, natural))
    println(ascending.binarySearch(6, natural, fromIndex = 1))
    println(ascending.binarySearch(6, natural, toIndex = 4))
    println(ascending.binarySearch(6, natural, fromIndex = 1, toIndex = 4))

    println("=== reversed comparator ===")
    println(descending.binarySearch(5, reversed))
    println(descending.binarySearch(6, reversed, fromIndex = 1))
}
