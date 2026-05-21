fun main() {
    val totals = sequenceOf(1, 2, 3)
        .scan(10) { acc, value -> acc + value }
        .toList()
    println(totals)

    val lengths = sequenceOf("a", "bb", "ccc")
        .scan(0) { acc, value -> acc + value.length }
        .toList()
    println(lengths)

    val empty = emptySequence<Int>()
        .scan(7) { acc, value -> acc + value }
        .toList()
    println(empty)
}
