fun main() {
    // sequenceOf: basic
    val s1 = sequenceOf(1, 2, 3).toList()
    println(s1)

    // sequenceOf: single element
    val single = sequenceOf(42).toList()
    println(single)

    // sequenceOf: strings
    val strs = sequenceOf("hello", "world").toList()
    println(strs)

    // sequenceOf: count and first/last
    println(sequenceOf(10, 20, 30).count())
    println(sequenceOf(10, 20, 30).first())
    println(sequenceOf(10, 20, 30).last())

    // generateSequence: with null termination
    val s2 = generateSequence(1) { if (it < 16) it * 2 else null }.toList()
    println(s2)

    // generateSequence: infinite with take
    val s3 = generateSequence(1) { it * 2 }.take(5).toList()
    println(s3)

    // generateSequence: seed function (nullable seed)
    val s4 = generateSequence({ 10 }) { if (it > 1) it / 2 else null }.toList()
    println(s4)

    // chained operations on sequenceOf
    val chained = sequenceOf(1, 2, 3, 4, 5)
        .filter { it % 2 != 0 }
        .map { it * it }
        .toList()
    println(chained)
}
// SKIP-DIFF: sequence parity pending
