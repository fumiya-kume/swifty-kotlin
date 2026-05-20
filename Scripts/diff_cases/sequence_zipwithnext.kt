fun main() {
    val pairs = sequenceOf(1, 2, 3, 4).zipWithNext().toList()
    println(pairs)

    val firstPair = sequenceOf(1, 2, 3, 4).zipWithNext().take(1).toList()
    println(firstPair)

    val diffs = sequenceOf(1, 3, 6, 10).zipWithNext { left, right -> right - left }.toList()
    println(diffs)

    val firstDiff = sequenceOf(1, 3, 6, 10).zipWithNext { left, right -> right - left }.take(1).toList()
    println(firstDiff)

    val single = sequenceOf(42).zipWithNext().toList()
    println(single)
}
