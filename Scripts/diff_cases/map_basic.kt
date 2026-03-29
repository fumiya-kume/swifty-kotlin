fun main() {
    // Basic operations
    val map = mapOf("a" to 1, "b" to 2, "c" to 3)
    println(map["a"])
    println(map.containsKey("b"))
    println(map.containsValue(3))
    println(map.size)
    println(map.isEmpty())

    // Views
    println(map.keys.sorted())
    println(map.values.sorted())

    // Transformation
    val doubled = map.mapValues { it.value * 2 }
    println(doubled.entries.map { "${it.key}=${it.value}" }.sorted())

    val upper = map.mapKeys { it.key.uppercase() }
    println(upper.entries.map { "${it.key}=${it.value}" }.sorted())

    // Filter operations
    val filtered = map.filter { it.value > 1 }
    println(filtered.entries.map { "${it.key}=${it.value}" }.sorted())

    val filteredValues = map.filterValues { v -> v < 3 }
    println(filteredValues.entries.map { "${it.key}=${it.value}" }.sorted())

    val filteredValues2 = map.filterValues { v -> v == 2 }
    println(filteredValues2.entries.map { "${it.key}=${it.value}" }.sorted())

    val filteredKeys = map.filterKeys { k -> k == "a" || k == "b" }
    println(filteredKeys.entries.map { "${it.key}=${it.value}" }.sorted())

    // Aggregation
    println(map.count { it.value > 1 })

    // MutableMap operations
    val mutable = mutableMapOf("x" to 10, "y" to 20)
    mutable.put("z", 30)
    mutable.remove("x")
    println(mutable.entries.map { "${it.key}=${it.value}" }.sorted())

    val mutable2 = mutableMapOf("x" to 1)
    mutable2.putAll(mapOf("a" to 100, "b" to 200))
    println(mutable2.entries.map { "${it.key}=${it.value}" }.sorted())

    val mutable3 = mutableMapOf("p" to 1, "q" to 2)
    mutable3.clear()
    println(mutable3.isEmpty())
}
