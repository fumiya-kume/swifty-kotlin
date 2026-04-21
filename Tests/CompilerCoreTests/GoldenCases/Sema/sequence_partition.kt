fun main() {
    // Basic partition on sequenceOf
    val seq = sequenceOf(1, 2, 3, 4, 5)
    val (evens, odds) = seq.partition { it % 2 == 0 }
    println(evens)   // [2, 4]
    println(odds)    // [1, 3, 5]

    // Partition on empty sequence
    val emptySeq = emptySequence<Int>()
    val (matchEmpty, noMatchEmpty) = emptySeq.partition { it > 0 }
    println(matchEmpty)    // []
    println(noMatchEmpty)  // []

    // Partition on asSequence()
    val list = listOf(10, 20, 30, 40, 50)
    val (big, small) = list.asSequence().partition { it >= 30 }
    println(big)    // [30, 40, 50]
    println(small)  // [10, 20]

    // All match
    val allMatch = sequenceOf(2, 4, 6).partition { it % 2 == 0 }
    println(allMatch.first)   // [2, 4, 6]
    println(allMatch.second)  // []

    // None match
    val noneMatch = sequenceOf(1, 3, 5).partition { it % 2 == 0 }
    println(noneMatch.first)   // []
    println(noneMatch.second)  // [1, 3, 5]
}
