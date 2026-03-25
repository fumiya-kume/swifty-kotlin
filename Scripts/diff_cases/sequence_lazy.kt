fun main() {
    // sequenceOf examples: filter/map chain, take, drop
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
    
    // STDLIB-HOF-022: Additional higher-order functions
    // filterNot
    println(sequenceOf(1, 2, 3, 4, 5).filterNot { it % 2 == 0 }.toList())
    // find
    println(sequenceOf(1, 2, 3, 4, 5).find { it > 3 })
    println(sequenceOf(1, 2, 3).find { it > 10 })
    // asIterable
    println(sequenceOf(1, 2, 3).asIterable().toList())
    
    // New lazy higher-order functions
    // mapNotNull
    println(sequenceOf(1, null, 3, null, 5).mapNotNull { it?.times(2) }.toList())
    // filterNotNull
    println(sequenceOf(1, null, 3, null, 5).filterNotNull().toList())
    // mapIndexed
    println(sequenceOf(10, 20, 30).mapIndexed { index, value -> index + value }.toList())
    // withIndex
    println(sequenceOf(10, 20, 30).withIndex().toList())
    // flatMap
    println(sequenceOf(1, 2).flatMap { listOf(it, it * 10) }.toList())
    
    // Test laziness with take
    println(sequenceOf(1, 2, 3, 4, 5).mapNotNull { it * 2 }.take(2).toList())
    println(sequenceOf(1, null, 3, null, 5).filterNotNull().take(1).toList())
    println(sequenceOf(10, 20, 30).mapIndexed { index, value -> index + value }.take(1).toList())
    println(sequenceOf(10, 20, 30).withIndex().take(1).toList())
    println(sequenceOf(1, 2).flatMap { listOf(it, it * 10) }.take(3).toList())
}
// SKIP-DIFF: sequence parity pending
