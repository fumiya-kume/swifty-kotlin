// KSP-977: Iterable<T>.forEach must execute the action in iteration order,
// exactly once per element, including nullable elements and a custom one-shot
// Iterable implementation. Receiver-specific forEach overloads remain isolated.

class OneShotIterable<T>(private val values: List<T>) : Iterable<T> {
    private var consumed = false

    override fun iterator(): Iterator<T> {
        if (consumed) error("iterator reused")
        consumed = true
        return values.iterator()
    }
}

fun main() {
    val events = StringBuilder()
    val nullableValues: Iterable<String?> = OneShotIterable(listOf(null, "b", "c"))
    nullableValues.forEach { value ->
        if (events.length > 0) events.append("|")
        events.append(value ?: "null")
    }
    println(events.toString())

    val empty: Iterable<Int> = emptyList()
    var emptyCalls = 0
    empty.forEach { emptyCalls += 1 }
    println("empty:$emptyCalls")

    val custom = OneShotIterable(listOf(1, 2, 3))
    var visited = 0
    try {
        custom.forEach { value ->
            visited += value
            if (value == 2) throw IllegalStateException("stop")
        }
    } catch (e: IllegalStateException) {
        println("caught")
    }
    println("visited:$visited")
}

// Compile-only receiver isolation: these calls must retain their existing
// receiver-specific declarations and are intentionally not executed here.
fun receiverResolution() {
    var listTotal = 0
    listOf(4, 5).forEach { listTotal += it }
    println("list:$listTotal")

    var arrayTotal = 0
    arrayOf(6, 7).forEach { arrayTotal += it }
    println("array:$arrayTotal")

    var mapTotal = 0
    mapOf("x" to 8).forEach { _, value -> mapTotal += value }
    println("map:$mapTotal")

    var sequenceTotal = 0
    sequenceOf(9, 10).forEach { sequenceTotal += it }
    println("sequence:$sequenceTotal")

    var iteratorTotal = 0
    listOf(11, 12).iterator().forEach { iteratorTotal += it }
    println("iterator:$iteratorTotal")

    var indexedTotal = 0
    listOf(13, 14).forEachIndexed { index, value -> indexedTotal += index + value }
    println("indexed:$indexedTotal")

    var primitiveTotal = 0
    intArrayOf(15, 16).forEach { primitiveTotal += it }
    println("primitive:$primitiveTotal")
}
