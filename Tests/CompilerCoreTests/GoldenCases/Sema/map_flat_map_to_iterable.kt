// RF-FIXTURE-018: Map<K,V>.flatMapTo(destination, transform) — a transform
// returning Iterable<R> resolves the Iterable overload, sees the entry as
// Map.Entry<K, V>, and returns the same mutable destination C. Destination
// identity, append order, and call counts are executed by
// Scripts/diff_cases/stdlib_kotlin_collections_Map_flat.kt.
fun flatMapIterable(
    source: Map<String, Int>,
    destination: MutableList<Any>
) {
    val result = source.flatMapTo(destination) { entry ->
        listOf(entry.key, entry.value, "iterable")
    }
    val checked: MutableList<Any> = result
}

fun flatMapIterableNullable(
    source: Map<String?, Int?>,
    destination: MutableList<Any?>
) {
    val result = source.flatMapTo(destination) { entry ->
        listOf(entry.key, entry.value, null)
    }
    val checked: MutableList<Any?> = result
}
