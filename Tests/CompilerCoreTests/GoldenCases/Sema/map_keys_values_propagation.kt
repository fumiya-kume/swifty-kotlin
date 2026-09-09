// RF-FIXTURE-003: mapValues keeps K while transforming V, mapKeys keeps V while
// transforming K; both take an it: Map.Entry<K, V> lambda.

fun mapValuesTransform(values: Map<String, Int>) {
    val doubled = values.mapValues { it.value * 2 }
    val checked: Map<String, Int> = doubled
}

fun mapKeysTransform(values: Map<String, Int>) {
    val byLength = values.mapKeys { it.key.length }
    val checked: Map<Int, Int> = byLength
}
