fun main() {
    val seq = sequenceOf(10, 20, 30, 40)

    seq.forEachIndexed { i, v -> println("$i:$v") }
    // 0:10
    // 1:20
    // 2:30
    // 3:40

    val pairs = sequenceOf(1, 2, 3, 4).zipWithNext().toList()
    println(pairs)  // [(1, 2), (2, 3), (3, 4)]

    val diffs = sequenceOf(1, 3, 6, 10).zipWithNext { a, b -> b - a }
    println(diffs.toList())  // [2, 3, 4]
}
