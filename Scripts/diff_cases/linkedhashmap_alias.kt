fun main() {
    val lhm: MutableMap<String, Int> = LinkedHashMap<String, Int>()
    lhm["z"] = 26
    lhm["a"] = 1
    lhm["m"] = 13
    println(lhm)
    println(lhm.keys.toList())
    println(lhm.values.toList())
    println(lhm.entries.map { "${it.key}=${it.value}" })
    lhm["z"] = 99
    println(lhm)
    lhm.remove("a")
    println(lhm.size)
    println(lhm.containsKey("m"))
    println(lhm.containsValue(99))
    lhm.putAll(mapOf("x" to 24, "y" to 25))
    println(lhm.keys.toList())
}
