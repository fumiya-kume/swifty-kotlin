fun main() {
    val map = mutableMapOf("a" to 1)
    map.putAll(mapOf("b" to 2, "c" to 3))
    println(map)
    map.putAll(mapOf("a" to 10))
    println(map)
}
