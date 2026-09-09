// RF-FIXTURE-003: Map.toList() converts Map<K, V> to List<Pair<K, V>>.

fun toListOfPairs(values: Map<String, Int>) {
    val pairs = values.toList()
    val checked: List<Pair<String, Int>> = pairs
}
