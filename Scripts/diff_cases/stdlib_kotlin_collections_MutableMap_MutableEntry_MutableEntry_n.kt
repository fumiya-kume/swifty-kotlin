fun main() {
    val map: MutableMap<String, Int> = mutableMapOf("key" to 1)
    val entry = map.iterator().next()
    println(entry.setValue(42))
    println(entry.value)
    println(map["key"])
}
