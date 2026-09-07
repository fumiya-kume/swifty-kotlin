// MutableSet inherits iterator declarations through both Set and MutableIterable.
fun main() {
    val map = mutableMapOf("one" to 1, "two" to 2)
    val entries: MutableSet<MutableMap.MutableEntry<String, Int>> = map.entries
    val iterator = entries.iterator()
    val entry = iterator.next()
    println(entry.key)
    println(entry.setValue(42))
    println(map["one"])
    iterator.remove()
    println(map)
}
