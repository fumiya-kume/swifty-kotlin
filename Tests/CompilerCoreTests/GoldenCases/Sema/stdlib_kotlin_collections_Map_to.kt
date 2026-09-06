package golden.sema

fun <K, V> copyMap(source: Map<out K, V>): Map<K, V> = source.toMap()

fun <K, V, C : MutableMap<in K, in V>> copyInto(
    source: Map<out K, V>,
    destination: C,
): C = source.toMap(destination)

fun main() {
    val source: Map<String?, Int?> = mapOf(null to null, "b" to 2)
    val copied = copyMap(source)
    val destination: MutableMap<Any?, Any?> = mutableMapOf("keep" to 9, "b" to 0)
    val returned = copyInto(source, destination)
    println(copied)
    println(returned === destination)
    println(destination)
}
