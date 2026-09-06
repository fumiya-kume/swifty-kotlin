// KSP-946: source-backed MutableMap with residual mutation and view dispatch.
fun main() {
    val map: MutableMap<String, Int?> = mutableMapOf("present" to 1, "nullable" to null)
    map["present"] = 2
    println(map.put("present", null) ?: -1)
    println(map.put("missing", 3) ?: -2)
    println(map.remove("missing") ?: -3)
    println(map.remove("missing") ?: -4)
    map.putAll(mapOf("from" to 4))
    println(map.keys.sorted())
    println(map.values.toList().map { it ?: -5 }.sorted())
    println(map.entries.map { "${it.key}:${it.value ?: -6}" }.sorted())
    map.clear()
    println(map.isEmpty())
}
