fun inspectScan(source: CharSequence) {
    val scanned: List<Int> = source.scan(0) { acc, value -> acc + value.code }
    val indexed: List<String> = source.scanIndexed("") { index, acc, value ->
        acc + index + value
    }
    println(scanned)
    println(indexed)
}

fun inspectNullable(source: CharSequence?) {
    val scanned = source?.scan<String?>(null) { acc, value ->
        if (acc == null) value.toString() else acc + value
    }
    val indexed = source?.scanIndexed(0) { index, acc, _ -> acc + index }
    println(scanned)
    println(indexed)
}

fun inspectNamed(source: CharSequence, seed: Int) {
    val scanned = source.scan(initial = seed, operation = { acc, value -> acc + value.code })
    val indexed = source.scanIndexed(initial = "", operation = { index, acc, value ->
        acc + index + value
    })
    println(scanned)
    println(indexed)
}
