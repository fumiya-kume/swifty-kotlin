// MutableSet inherits iterator declarations through both Set and MutableIterable.
fun main() {
    val map = mutableMapOf("one" to 1, "two" to 2)
    val entries = map.entries
    val iterator = entries.iterator()
    val entry = iterator.next()
    println(entry.key)
    println(entry.value)
    println(iterator.next().key)
    println(iterator.hasNext())
}
