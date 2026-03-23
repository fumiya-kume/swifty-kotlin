fun main() {
    // Basic map operations
    val map = mapOf("a" to 1, "b" to 2, "c" to 3)
    println(map)
    println(map.size)
    println(map["a"])
    println(map["b"])
    println(map.containsKey("a"))
    println(map.containsKey("z"))

    // Map.minus with single key
    val map2 = map - "a"
    println(map2)

    // Map.minus with key not present (no-op)
    val map3 = map - "z"
    println(map3)

    // Original map is unchanged (immutability)
    println(map)

    // Map<Int, String>
    val intMap = mapOf(1 to "one", 2 to "two", 3 to "three")
    println(intMap)
    val intMap2 = intMap - 1
    println(intMap2)
}
