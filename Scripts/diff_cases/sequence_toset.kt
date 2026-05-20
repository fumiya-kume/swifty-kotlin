fun main() {
    val set = sequenceOf(3, 1, 2, 1, 3).toSet()
    println(set)
    println(set.contains(1))
    println(set.contains(99))

    val empty = emptySequence<Int>().toSet()
    println(empty)
}
