// RF-FIXTURE-018: Map<K,V>.flatMapTo(destination, transform) — a transform
// returning Sequence<R> (including a constrainOnce() chain) resolves the
// Sequence overload and returns the same mutable destination C.
// Scripts/diff_cases/stdlib_kotlin_collections_Map_flat.kt executes the
// one-shot / exception scenarios.
fun flatMapSequence(
    source: Map<String, Int>,
    destination: MutableList<Any>
) {
    val result = source.flatMapTo(destination) { entry ->
        sequenceOf(entry.key, entry.value, "sequence").constrainOnce()
    }
    val checked: MutableList<Any> = result
}

fun flatMapSequenceNullable(
    source: Map<String?, Int?>,
    destination: MutableList<Any?>
) {
    val result = source.flatMapTo(destination) { entry ->
        sequenceOf<Any?>(entry.key, entry.value, null).constrainOnce()
    }
    val checked: MutableList<Any?> = result
}
