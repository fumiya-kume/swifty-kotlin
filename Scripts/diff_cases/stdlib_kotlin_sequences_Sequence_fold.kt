fun main() {
    val values: Sequence<Int> = sequenceOf(1, 2, 3)
    println(values.fold(0) { acc, value -> acc + value })
    println(values.foldIndexed(0) { index, acc, value -> acc + index * value })

    val empty: Sequence<Int> = emptySequence()
    println(empty.fold(42) { acc, value -> acc + value })
    println(empty.foldIndexed(99) { index, acc, value -> acc + index + value })
}
