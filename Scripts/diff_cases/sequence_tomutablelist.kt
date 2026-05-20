fun main() {
    val mutableList = sequenceOf(3, 1, 2, 1, 3).toMutableList()
    mutableList.add(99)
    println(mutableList)

    val empty = emptySequence<Int>().toMutableList()
    empty.add(7)
    println(empty)
}
