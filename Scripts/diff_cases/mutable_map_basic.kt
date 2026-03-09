fun main() {
    val map = mutableMapOf("a" to 1)
    map["b"] = 2
    println(map)
    println(map.containsKey("a"))
    println(map.put("a", 3))
    println(map)
    println(map.remove("b"))
    println(map)
    println(emptyMap<String, Int>().isEmpty())
}
