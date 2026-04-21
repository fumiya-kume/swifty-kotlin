fun testFlatMapTo(values: List<String>) {
    val dest = mutableListOf<String>()
    val result = values.flatMapTo(dest) { listOf(it, it.uppercase()) }
}

fun testFlatMapIndexedTo(values: List<String>) {
    val dest = mutableListOf<String>()
    val result = values.flatMapIndexedTo(dest) { index, item -> listOf("$index: $item", item.uppercase()) }
}
