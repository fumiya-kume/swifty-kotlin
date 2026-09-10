// RF-FIXTURE-010: Sequence<Iterable<T>>.flatten() resolves through the
// Iterable flatten overload and returns Sequence<T>.

fun flattenIterables(lists: Sequence<List<Int>>) {
    val flattened = lists.flatten()
    val checked: Sequence<Int> = flattened
}

fun flattenIterableParams(lists: Sequence<Iterable<Int>>) {
    val flattened = lists.flatten()
    val checked: Sequence<Int> = flattened
}
