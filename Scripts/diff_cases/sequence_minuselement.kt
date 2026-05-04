fun main() {
    val values = sequenceOf(1, 2, 3, 2)

    println(values.minusElement(2).toList())
    println(values.minusElement(9).toList())
    println(emptySequence<Int>().minusElement(1).toList())
}
