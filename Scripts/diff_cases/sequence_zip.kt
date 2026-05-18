fun main() {
    val equal = sequenceOf(1, 2, 3).zip(sequenceOf("a", "b", "c")).toList()
    println(equal)

    val leftLonger = sequenceOf(1, 2, 3, 4).zip(sequenceOf("x", "y")).toList()
    println(leftLonger)

    val rightLonger = sequenceOf("left").zip(sequenceOf(10, 20, 30)).toList()
    println(rightLonger)

    val empty = emptySequence<Int>().zip(sequenceOf("unused")).toList()
    println(empty)
}
