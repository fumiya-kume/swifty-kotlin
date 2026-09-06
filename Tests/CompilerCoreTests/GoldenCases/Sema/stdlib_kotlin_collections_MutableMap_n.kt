fun main() {
    val map: MutableMap<String, Int?> = mutableMapOf("a" to 1, "nullable" to null)
    println(map.getOrPut("nullable") { 2 })
    println(map.getOrPut("missing") { null })
    map -= "a"
    map -= listOf("missing")
    map -= sequenceOf("none")
    map -= arrayOf("none2")
    map += ("x" to 10)
    map += listOf("x" to 11, "y" to 12)
    map += sequenceOf("y" to 13, "z" to 14)
    map += arrayOf("z" to 15, "w" to 16)
    map += mapOf("w" to 17, "v" to 18)
    map.putAll(listOf("v" to 19, "u" to 20))
    map.putAll(sequenceOf("u" to 21, "t" to 22))
    map.putAll(arrayOf("t" to 23, "s" to 24))
    map["set"] = 25
    println(map.remove("nullable"))
    println(map.remove("absent"))
    val delegatedMap: MutableMap<String, Int> = mutableMapOf()
    var delegated: Int by delegatedMap
    delegated = 31
    println(delegated)
    val defaulted = map.withDefault { key -> if (key == "null") null else key.length }
    println(defaulted.getValue("null"))
    defaulted["wrapper"] = 26
    println(map["wrapper"])
    val iterator = map.iterator()
    if (iterator.hasNext()) {
        val entry = iterator.next()
        println(entry.key)
        entry.setValue(999)
        iterator.remove()
    }
    println(map)
}
