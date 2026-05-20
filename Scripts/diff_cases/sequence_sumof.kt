fun main() {
    println(sequenceOf(1, 2, 3).sumOf { value -> if (value == 2) 10 else value })
    println(emptySequence<Int>().sumOf { value -> value * 10 })
    println(sequenceOf(-3, 5, -2).sumOf { value -> value * value })
}
