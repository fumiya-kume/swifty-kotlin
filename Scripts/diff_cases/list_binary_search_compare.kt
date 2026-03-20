fun main() {
    val list = listOf(1, 5, 10, 15, 20, 25, 30)

    // Find element 15 using comparison lambda
    val idx = list.binarySearch { it - 15 }
    println(idx) // 3

    // Element not found (between 10 and 15)
    val missing = list.binarySearch { it - 12 }
    println(missing) // negative (insertion point encoded)

    // First element
    val first = list.binarySearch { it - 1 }
    println(first) // 0

    // Last element
    val last = list.binarySearch { it - 30 }
    println(last) // 6

    // Element smaller than all
    val tooSmall = list.binarySearch { it - (-1) }
    println(tooSmall) // negative

    // Element larger than all
    val tooLarge = list.binarySearch { it - 100 }
    println(tooLarge) // negative
}
