// RF-FIXTURE-009: groupBy buckets elements into Map<K, List<T>> and partition
// splits into a Pair of Lists that supports destructuring.

fun group(values: List<String>) {
    val grouped = values.groupBy { it.length }
    val checked: Map<Int, List<String>> = grouped
}

fun split(values: List<String>) {
    val (matching, rest) = values.partition { it.length > 3 }
    val checkedMatching: List<String> = matching
    val checkedRest: List<String> = rest
}
