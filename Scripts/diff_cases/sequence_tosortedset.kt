fun main() {
    val sortedSet = sequenceOf(3, 1, 2, 1, 3).toSortedSet()
    println(sortedSet)
    println(sortedSet.contains(1))
    println(sortedSet.contains(99))

    val empty = emptySequence<Int>().toSortedSet()
    println(empty)
}
