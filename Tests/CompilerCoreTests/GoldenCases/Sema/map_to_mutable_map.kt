// RF-FIXTURE-004: Map.toMutableMap returns a MutableMap<K, V> copy.

fun mapToMutableMap(map: Map<String, Int>) {
    val mutable = map.toMutableMap()
    val checked: MutableMap<String, Int> = mutable
}
