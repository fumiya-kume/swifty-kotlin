fun main() {
    // sequenceOf: each call demonstrates an independent chain of operations
    println(sequenceOf(1, 2, 3, 4, 5).filter { it > 2 }.map { it * 10 }.toList())
    println(sequenceOf(1, 2, 3, 4, 5).take(3).toList())
    println(sequenceOf(1, 2, 3, 4, 5).drop(2).toList())
    // asSequence from Iterable/List
    val result = listOf(1, 2, 3, 4, 5)
        .asSequence()
        .map { it * 2 }
        .filter { it > 4 }
        .toList()
    println(result)
    // generateSequence
    println(generateSequence(1) { if (it < 10) it * 2 else null }.toList())
}
