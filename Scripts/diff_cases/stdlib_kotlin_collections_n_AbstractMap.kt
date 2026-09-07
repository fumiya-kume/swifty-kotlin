// KSP-928: AbstractMap is source-backed while Map entry materialization remains
// on the shared collection runtime path.

import kotlin.collections.AbstractMap
import kotlin.collections.Map
import kotlin.collections.Set

class ProbeMap : AbstractMap<String, Int?>() {
    override val entries: Set<Map.Entry<String, Int?>>
        get() = mutableMapOf<String, Int?>(
            "one" to 1,
            "missing" to null,
        ).entries
}

fun main() {
    val map = ProbeMap()
    println(map.size)
    println(map["one"])
    println(map["missing"] == null)
    println(map["absent"] == null)
    println(map.containsKey("missing"))
    println(map.containsKey("absent"))
    println(map.containsValue(null))
    println(map.entries)
    println(map.keys)
    println(map.values)
    println(map == ProbeMap())
    println(map == mapOf<String, Int?>("one" to 1, "missing" to null))
    println(map.hashCode() == ProbeMap().hashCode())
    println(map.toString())
}
