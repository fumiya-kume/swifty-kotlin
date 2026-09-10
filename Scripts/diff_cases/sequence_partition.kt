// Sequence.partition execution coverage: asSequence receivers, all-match, and
// none-match results (basic and empty are covered by the
// testCodegenSequencePartitionSplitsElements codegen test).
fun main() {
    // Partition on asSequence()
    val list = listOf(10, 20, 30, 40, 50)
    val (big, small) = list.asSequence().partition { it >= 30 }
    println(big)
    println(small)

    // All match
    val allMatch = sequenceOf(2, 4, 6).partition { it % 2 == 0 }
    println(allMatch.first)
    println(allMatch.second)

    // None match
    val noneMatch = sequenceOf(1, 3, 5).partition { it % 2 == 0 }
    println(noneMatch.first)
    println(noneMatch.second)
}
