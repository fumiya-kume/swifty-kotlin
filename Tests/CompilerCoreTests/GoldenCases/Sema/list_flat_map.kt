// RF-FIXTURE-009: List.flatMap flattens the lambda's Iterable<R> result into
// List<R>.

fun flat(values: List<String>) {
    val flattened = values.flatMap { listOf(it) }
    val checked: List<String> = flattened
}
