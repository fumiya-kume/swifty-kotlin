fun <K, V> copyMap(source: Map<out K, V>): Map<K, V> = source.toMap()

fun <K, V, C : MutableMap<in K, in V>> copyInto(
    source: Map<out K, V>,
    destination: C,
): C = source.toMap(destination)

fun main() {
    val empty: Map<String?, Int?> = mapOf()
    val single: Map<String?, Int?> = mapOf(null to null)
    val multi: Map<String?, Int?> = mapOf("a" to 1, null to null, "b" to 2)
    val emptyCopy = empty.toMap()
    val singleCopy = single.toMap()
    val multiCopy = multi.toMap()
    println("empty=$emptyCopy")
    println("single=$singleCopy")
    println("multi=$multiCopy")
    println("original=$multi")

    val destination: MutableMap<Any?, Any?> = mutableMapOf("keep" to 9, "a" to 0)
    val returned = multi.toMap(destination)
    println("same=${returned === destination}")
    println("destination=$destination")
    println("generic=${copyMap(multi)}")
    println("genericDestination=${copyInto(multi, mutableMapOf<String?, Int?>())}")
}
