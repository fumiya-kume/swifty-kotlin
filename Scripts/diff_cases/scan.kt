fun main() {
    // scan (alias for runningFold): accumulates with initial value, returns list including initial
    val numbers = listOf(1, 2, 3, 4, 5)
    val scanResult = numbers.scan(0) { acc, element -> acc + element }
    println(scanResult) // [0, 1, 3, 6, 10, 15]

    // runningFold: same as scan
    val runningFoldResult = numbers.runningFold(0) { acc, element -> acc + element }
    println(runningFoldResult) // [0, 1, 3, 6, 10, 15]

    // runningReduce: no initial value, starts from first element
    val runningReduceResult = numbers.runningReduce { acc, element -> acc + element }
    println(runningReduceResult) // [1, 3, 6, 10, 15]

    // scan with string accumulation
    val words = listOf("a", "b", "c", "d")
    val concatScan = words.scan("") { acc, s -> acc + s }
    println(concatScan) // [, a, ab, abc, abcd]

    // scan with multiplication
    val productScan = listOf(1, 2, 3, 4).scan(1) { acc, element -> acc * element }
    println(productScan) // [1, 1, 2, 6, 24]

    // runningReduce with multiplication
    val productRunning = listOf(1, 2, 3, 4).runningReduce { acc, element -> acc * element }
    println(productRunning) // [1, 2, 6, 24]

    // scan on empty list
    val emptyResult = emptyList<Int>().scan(0) { acc, element -> acc + element }
    println(emptyResult) // [0]

    // runningReduce on single element
    val singleResult = listOf(42).runningReduce { acc, element -> acc + element }
    println(singleResult) // [42]
}
