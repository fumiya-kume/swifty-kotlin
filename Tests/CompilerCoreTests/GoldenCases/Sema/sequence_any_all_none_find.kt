fun main() {
    val s = sequenceOf(1, 2, 3, 4, 5)
    val hasEven = s.any { it % 2 == 0 }
    val allPositive = s.all { it > 0 }
    val noneNegative = s.none { it < 0 }
    val firstEven = s.find { it % 2 == 0 }
    val nonEmpty = s.any()
    val emptySeq = emptySequence<Int>()
    val isEmpty = emptySeq.none()
    println(hasEven)
    println(allPositive)
    println(noneNegative)
    println(firstEven)
    println(nonEmpty)
    println(isEmpty)
}
