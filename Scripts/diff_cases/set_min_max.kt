fun main() {
    val set = setOf(3, 1, 4, 1, 5, 9, 2, 6)
    println(set.minOrNull())  // 1
    println(set.maxOrNull())  // 9

    val empty = emptySet<Int>()
    println(empty.minOrNull())  // null
    println(empty.maxOrNull())  // null
}
