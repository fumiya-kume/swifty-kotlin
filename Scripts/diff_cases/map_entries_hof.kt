fun main() {
    val map = mapOf("a" to 1, "b" to 2, "c" to 3)
    println(map.entries.map { "${it.key}=${it.value}" })
    println(map.keys.sorted())
    println(map.values.sorted())
    println(map.filter { it.value > 1 })
    println(map.mapValues { it.value * 10 })
    println(map.mapKeys { it.key.uppercase() })
    println(map.any { it.value > 2 })
    println(map.all { it.value > 0 })
    println(map.none { it.value > 5 })
    println(map.count { it.value % 2 != 0 })
}
