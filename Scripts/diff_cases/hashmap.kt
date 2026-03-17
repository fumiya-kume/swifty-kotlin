fun main() {
    val map = HashMap<String, Int>()
    map["a"] = 1
    map["b"] = 2
    map["c"] = 3
    println(map.size)
    println(map["b"])
    println(map.containsKey("a"))
    println(map.containsValue(3))
    map.remove("b")
    println(map.size)
    println(map is MutableMap<*, *>)
}
