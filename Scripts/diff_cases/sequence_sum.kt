fun main() {
    println(sequenceOf(1, 2, 3, 4).sum())
    println(emptySequence<Int>().sum())
    println(sequenceOf(-3, 5, -2).sum())
}
