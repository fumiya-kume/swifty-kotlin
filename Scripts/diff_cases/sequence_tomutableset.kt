fun main() {
    val mutableSet = sequenceOf(3, 1, 2, 1, 3).toMutableSet()
    mutableSet.add(42)
    println(mutableSet)

    val empty = emptySequence<Int>().toMutableSet()
    empty.add(7)
    println(empty)
}
