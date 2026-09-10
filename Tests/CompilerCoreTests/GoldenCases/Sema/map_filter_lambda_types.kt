// RF-FIXTURE-003: Map.map / Map.filter take a destructured Map.Entry lambda and
// propagate the lambda result into List<R> / Map<K, V> return types.

fun mapDestructured(values: Map<String, Int>) {
    val lengths = values.map { (key, value) ->
        val checkedKey: String = key
        val checkedValue: Int = value
        checkedValue
    }
    val checked: List<Int> = lengths
}

fun filterDestructured(values: Map<String, Int>) {
    val filtered = values.filter { (_, value) -> value > 1 }
    val checked: Map<String, Int> = filtered
}
