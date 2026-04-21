fun main() {
    val seq = sequenceOf(1, 2, 3, 4, 5)

    // filterTo: append matching elements to destination
    val dest1 = mutableListOf<Int>()
    seq.filterTo(dest1) { it > 2 }
    println(dest1)

    // filterNotTo: append non-matching elements to destination
    val dest2 = mutableListOf<Int>()
    seq.filterNotTo(dest2) { it > 2 }
    println(dest2)

    // filterIndexedTo: append elements where indexed predicate matches
    val dest3 = mutableListOf<Int>()
    seq.filterIndexedTo(dest3) { index, value -> index % 2 == 0 }
    println(dest3)

    // filterNotNullTo: append non-null elements to destination
    val seqNullable = sequenceOf(1, null, 2, null, 3)
    val dest4 = mutableListOf<Int>()
    seqNullable.filterNotNullTo(dest4)
    println(dest4)
}
