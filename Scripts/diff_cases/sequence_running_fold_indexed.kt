fun main() {
    val weighted = sequenceOf(1, 2, 3, 4)
        .runningFoldIndexed(100) { index, acc, value -> acc + index * value }
        .toList()
    println(weighted)

    val scanned = sequenceOf("a", "bb", "ccc")
        .scanIndexed(0) { index, acc, value -> acc + index + value.length }
        .toList()
    println(scanned)

    val empty = emptySequence<Int>()
        .runningFoldIndexed(7) { index, acc, value -> acc + index + value }
        .toList()
    println(empty)
}
