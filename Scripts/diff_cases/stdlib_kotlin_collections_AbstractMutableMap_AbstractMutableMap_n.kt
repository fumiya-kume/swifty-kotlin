import kotlin.collections.AbstractMutableMap
import kotlin.collections.MutableMap
import kotlin.collections.MutableSet

class ProbeMutableMap : AbstractMutableMap<String, Int>() {
    private val backing = mutableMapOf<String, Int>()
    private var putCount = 0

    override val entries: MutableSet<MutableMap.MutableEntry<String, Int>>
        get() = backing.entries

    override fun put(key: String, value: Int): Int? {
        putCount += 1
        return backing.put(key, value)
    }

    fun numberOfPuts(): Int = putCount
}

fun main() {
    val map = ProbeMutableMap()
    val abstractMap: AbstractMutableMap<String, Int> = map
    abstractMap.putAll(mapOf("b" to 2))
    println(map.numberOfPuts())
    val keys = abstractMap.keys
    val values = abstractMap.values
    println("${keys.size}:${values.size}")
    println(abstractMap.remove("missing"))
    println(abstractMap.remove("b"))
    abstractMap.put("c", 3)
    abstractMap.clear()
    println(map.numberOfPuts())
}
