fun main() {
    val seq = sequenceOf(3, 1, 2, 1, 3)

    val mutableList: MutableList<Int> = seq.toMutableList()
    mutableList.add(99)
    println(mutableList)

    val mutableSet: MutableSet<Int> = sequenceOf(3, 1, 2, 1, 3).toMutableSet()
    mutableSet.add(42)
    println(mutableSet)

    val hashSet: MutableSet<Int> = sequenceOf(3, 1, 2, 1, 3).toHashSet()
    hashSet.add(77)
    println(hashSet)
}
