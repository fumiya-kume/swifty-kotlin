fun main() {
    // Basic Map.plus with Pair
    val map = mapOf("a" to 1, "b" to 2)
    val map2 = map + ("c" to 3)
    println(map2)

    // Map.plus overwrites existing key
    val map3 = map + ("a" to 99)
    println(map3)

    // Map.plus with another Map
    val other = mapOf("c" to 3, "d" to 4)
    val map4 = map + other
    println(map4)

    // Map.minus with single key
    val map5 = map - "a"
    println(map5)

    // Map.minus with list of keys
    val map6 = map4 - listOf("a", "c")
    println(map6)

    // Map.plus with Iterable<Pair>
    val pairs = listOf("x" to 10, "y" to 20)
    val map7 = map + pairs
    println(map7)

    // Map.plus with Sequence<Pair>
    val seq = sequenceOf("p" to 100, "q" to 200)
    val map8 = map + seq
    println(map8)

    // Map.plus with Array<Pair>
    val arr = arrayOf("m" to 50, "n" to 60)
    val map9 = map + arr
    println(map9)

    // Chained plus/minus
    val map10 = map + ("c" to 3) + ("d" to 4) - "a"
    println(map10)

    // Original map is unchanged (immutability)
    println(map)

    // Map.minus with key not present (no-op)
    val map11 = map - "z"
    println(map11)

    // Empty map plus
    val empty = emptyMap<String, Int>()
    val map12 = empty + ("a" to 1)
    println(map12)

    // Map.plus with empty map
    val map13 = map + emptyMap()
    println(map13)

    // Map.minus with empty list
    val map14 = map - listOf<String>()
    println(map14)

    // Map.plus with multiple duplicate keys in pairs (last wins)
    val map15 = map + listOf("a" to 100, "a" to 200)
    println(map15)

    // Map<Int, String> plus/minus
    val intMap = mapOf(1 to "one", 2 to "two")
    val intMap2 = intMap + (3 to "three")
    println(intMap2)
    val intMap3 = intMap - 1
    println(intMap3)
}
