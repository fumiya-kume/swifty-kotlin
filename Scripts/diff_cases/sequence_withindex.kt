fun main() {
    val indexed = sequenceOf(10, 20, 30).withIndex().toList()
    println(indexed)

    val first = sequenceOf(10, 20, 30).withIndex().take(1).toList()
    println(first)

    val empty = emptySequence<Int>().withIndex().toList()
    println(empty)
}
