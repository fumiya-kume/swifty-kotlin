fun main() {
    println(sequenceOf(1, 2, 3).averageOf { value -> value * 2 })
    println(sequenceOf("a", "bbb", "cc").averageOf { value -> value.length })
    println(emptySequence<Int>().averageOf { value -> value })
}
