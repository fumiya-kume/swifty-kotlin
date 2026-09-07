fun processLinkedMap(map: LinkedHashMap<String, Int>) {
    println(map.size)
}

fun createLinkedMap(): LinkedHashMap<Int, String> {
    return LinkedHashMap<Int, String>()
}

class OrderedMapHolder {
    val scores: LinkedHashMap<String, Int> = LinkedHashMap()
}

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

    // Alias-typed value passed to a LinkedHashMap parameter
    val aliasTyped: LinkedHashMap<String, Int> = LinkedHashMap()
    aliasTyped["p"] = 1
    aliasTyped["q"] = 2
    processLinkedMap(aliasTyped)

    // get: hit and miss
    val mutable: MutableMap<Int, String> = LinkedHashMap()
    mutable[1] = "one"
    mutable[2] = "two"
    mutable[3] = "three"
    println(mutable[1])
    println(mutable[99])

    // Views printed directly, without toList
    println(mutable.keys)
    println(mutable.values)
    println(mutable.entries)

    // for-destructuring keeps insertion order
    for ((key, value) in mutable) {
        println("$key=$value")
    }

    // Empty map
    val empty: MutableMap<String, Int> = LinkedHashMap()
    println(empty.size)
    println(empty.isEmpty())

    // Through a return value
    val created = createLinkedMap()
    created[1] = "one"
    println(created.size)

    // Through a property
    val holder = OrderedMapHolder()
    holder.scores["alice"] = 100
    holder.scores["bob"] = 90
    println(holder.scores.size)
    println(holder.scores)

    // Non-String type arguments
    val generic: LinkedHashMap<Double, Boolean> = LinkedHashMap()
    generic[1.5] = true
    generic[2.7] = false
    println(generic)
}
