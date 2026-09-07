fun mapFamily(
    source: Iterable<String?>,
    destination: MutableCollection<Any?>
): MutableCollection<Any?> {
    val mapped: List<String?> = source.map { it }
    val indexed: List<String> = source.mapIndexed { index, value -> "$index:${value ?: "null"}" }
    val indexedNotNull: List<String> = source.mapIndexedNotNull { index, value ->
        value?.let { "$index:$it" }
    }
    val indexedNotNullTo: MutableCollection<Any?> = source.mapIndexedNotNullTo(destination) { index, value ->
        value?.let { "$index:$it" }
    }
    val indexedTo: MutableCollection<Any?> = source.mapIndexedTo(destination) { index, value ->
        "$index:$value"
    }
    val notNull: List<String> = source.mapNotNull { it }
    val notNullTo: MutableCollection<Any?> = source.mapNotNullTo(destination) { it }
    val mappedTo: MutableCollection<Any?> = source.mapTo(destination) { it }
    return if (mapped.isEmpty() || indexed.isEmpty() || indexedNotNull.isEmpty()) {
        indexedNotNullTo
    } else if (indexedTo.isEmpty() || notNull.isEmpty() || notNullTo.isEmpty()) {
        mappedTo
    } else {
        destination
    }
}

fun main() {
    val destination = mutableListOf<Any?>("seed")
    mapFamily(listOf("a", null, "c"), destination)
}
