fun inspectRunning(source: CharSequence) {
    val folded: List<Int> = source.runningFold(0) { acc, value -> acc + value.code }
    val indexedFolded: List<String> = source.runningFoldIndexed("") { index, acc, value ->
        acc + index + value
    }
    val reduced: List<Char> = source.runningReduce { acc, value -> if (acc < value) value else acc }
    val indexedReduced: List<Char> = source.runningReduceIndexed { index, acc, value ->
        if (index % 2 == 0) value else acc
    }
    println(folded)
    println(indexedFolded)
    println(reduced)
    println(indexedReduced)
}

fun inspectNullable(source: CharSequence?) {
    val folded = source?.runningFold<String?>(null) { acc, value ->
        if (acc == null) value.toString() else acc + value
    }
    val indexedFolded = source?.runningFoldIndexed(0) { index, acc, _ -> acc + index }
    println(folded)
    println(indexedFolded)
}

fun inspectNamed(source: CharSequence, seed: Int) {
    val folded = source.runningFold(initial = seed, operation = { acc, value -> acc + value.code })
    val indexedFolded = source.runningFoldIndexed(initial = "", operation = { index, acc, value ->
        acc + index + value
    })
    println(folded)
    println(indexedFolded)
}
