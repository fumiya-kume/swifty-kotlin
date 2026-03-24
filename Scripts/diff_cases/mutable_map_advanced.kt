fun main() {
    val map = mutableMapOf("a" to 1, "b" to 2)
    println(map.getOrPut("c") { 3 })
    println(map.getOrPut("a") { 99 })
    println(map)
    map.putAll(mapOf("d" to 4, "e" to 5))
    println(map.size)
    println(map.keys.sorted())
    map.remove("b")
    println(map)
    map["f"] = 6
    println(map.containsKey("f"))
    println(map.containsValue(99))
}
