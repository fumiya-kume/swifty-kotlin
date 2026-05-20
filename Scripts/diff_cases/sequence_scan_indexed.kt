fun main() {
    val weighted = sequenceOf(1, 2, 3, 4)
        .scanIndexed(100) { index, acc, value -> acc + index * value }
        .toList()
    println(weighted)

    val lengths = sequenceOf("a", "bb", "ccc")
        .scanIndexed(0) { index, acc, value -> acc + index + value.length }
        .toList()
    println(lengths)

    val empty = emptySequence<Int>()
        .scanIndexed(7) { index, acc, value -> acc + index + value }
        .toList()
    println(empty)
}
