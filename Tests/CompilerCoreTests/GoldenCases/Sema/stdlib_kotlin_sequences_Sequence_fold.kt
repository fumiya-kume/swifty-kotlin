fun main() {
    val values: Sequence<Int> = sequenceOf(1, 2, 3)
    val folded = values.fold(0) { acc, value -> acc + value }
    val indexed = values.foldIndexed(0) { index, acc, value -> acc + index * value }
    println(folded)
    println(indexed)
}
