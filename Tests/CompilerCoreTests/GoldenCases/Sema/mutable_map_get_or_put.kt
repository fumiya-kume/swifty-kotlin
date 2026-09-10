// RF-FIXTURE-019: MutableMap getOrPut / indexed set / remove — nullable
// values, missing keys, and the remove return type. The null/absent runtime
// behavior is executed by the identical-input diff case
// stdlib_kotlin_collections_MutableMap_n.kt.
fun getOrPutNullable(map: MutableMap<String, Int?>, key: String) {
    val existing = map.getOrPut(key) { 2 }
    val checkedExisting: Int? = existing
    val missing = map.getOrPut("missing") { null }
    val checkedMissing: Int? = missing
}

fun setAndRemove(map: MutableMap<String, Int?>, key: String, value: Int?) {
    map[key] = value
    val removed = map.remove(key)
    val checked: Int? = removed
}
