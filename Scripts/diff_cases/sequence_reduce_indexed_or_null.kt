fun main() {
    println(
        sequenceOf(1, 2, 3, 4)
            .reduceIndexedOrNull { index, acc, value -> acc + index * value }
    )

    println(
        emptySequence<Int>()
            .reduceIndexedOrNull { index, acc, value -> acc + index * value }
    )

    println(
        sequenceOf(42)
            .reduceIndexedOrNull { index, acc, value -> acc + index * value }
    )
}
