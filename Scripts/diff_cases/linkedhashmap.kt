fun main() {
    val map = LinkedHashMap<String, Int>()
    map["c"] = 3
    map["a"] = 1
    map["b"] = 2
    println(map)
    println(map.keys.toList())
    println(map.values.toList())
    println(map.size)
}
