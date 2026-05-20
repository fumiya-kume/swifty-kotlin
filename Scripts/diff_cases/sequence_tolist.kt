fun main() {
    println(sequenceOf(3, 1, 2, 1, 3).toList())
    println(emptySequence<Int>().toList())
    println(sequenceOf("a", "bb").map { it.length }.toList())
}
