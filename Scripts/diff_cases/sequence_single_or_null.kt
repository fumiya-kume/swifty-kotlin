fun main() {
    println(sequenceOf(42).singleOrNull() ?: -1)
    println(emptySequence<Int>().singleOrNull() ?: -1)
    println(sequenceOf(1, 2).singleOrNull() ?: -1)
    println(sequenceOf("only").singleOrNull() ?: "missing")
}
