// RF-FIXTURE-011: Iterable<Iterable<T>>.flatten() — element type propagation
// and explicit type arguments on empty input. Empty / single / multiple /
// large-input values and ordering are executed by
// Scripts/diff_cases/flatten_core_test.kt.

fun flattenInts(lists: List<List<Int>>) {
    val flattened = lists.flatten()
    val checked: List<Int> = flattened
}

fun flattenStrings(lists: List<List<String>>) {
    val flattened = lists.flatten()
    val checked: List<String> = flattened
}

fun flattenEmpty() {
    val flattened = emptyList<List<Int>>().flatten()
    val checked: List<Int> = flattened
}
