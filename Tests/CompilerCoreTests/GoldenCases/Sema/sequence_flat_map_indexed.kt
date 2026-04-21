fun main() {
    val iterableResult = sequenceOf("a", "bc")
        .flatMapIndexed { index, value -> listOf(index.toString() + ":" + value, value + value) }
    val sequenceResult = sequenceOf("x", "yz")
        .flatMapIndexed { index, value -> sequenceOf(index.toString(), value) }

    println(iterableResult.toList())
    println(sequenceResult.toList())
}
