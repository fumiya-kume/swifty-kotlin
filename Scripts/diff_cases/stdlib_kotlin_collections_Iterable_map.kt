// KSP-982: exercise only the Iterable receiver overloads. The static receiver
// type stays Iterable<T> so concrete List/Array/Set/Sequence transform APIs
// are not the subject of this case.
class OneShot<T>(private val values: List<T>) : Iterable<T> {
    private var consumed = false

    override fun iterator(): Iterator<T> {
        if (consumed) throw IllegalStateException("one-shot iterable reused")
        consumed = true
        return values.iterator()
    }
}

fun main() {
    val empty: Iterable<Int> = OneShot(emptyList())
    println(empty.map { it + 1 })

    val values: Iterable<String?> = OneShot(listOf("a", null, "c"))
    var calls = 0
    println(values.map {
        calls += 1
        it ?: "null"
    })
    println(calls)

    val indexed: Iterable<String?> = OneShot(listOf("a", null, "c"))
    println(indexed.mapIndexed { index, value -> "$index:${value ?: "null"}" })

    val indexedNotNull: Iterable<String?> = OneShot(listOf("a", null, "c"))
    println(indexedNotNull.mapIndexedNotNull { index, value -> value?.let { "$index:$it" } })

    val destination = mutableListOf<Any?>("seed")
    val destinationValues: Iterable<String?> = OneShot(listOf("a", null, "c"))
    val returned = destinationValues.mapTo(destination) { it }
    println(returned === destination)
    println(destination)

    val indexedToValues: Iterable<String?> = OneShot(listOf("a", null, "c"))
    indexedToValues.mapIndexedTo(destination) { index, value -> if (index == 1) null else value }
    println(destination)

    val notNullToValues: Iterable<String?> = OneShot(listOf("a", null, "c"))
    notNullToValues.mapNotNullTo(destination) { it }
    println(destination)

    val indexedNotNullToValues: Iterable<String?> = OneShot(listOf("a", null, "c"))
    indexedNotNullToValues.mapIndexedNotNullTo(destination) { index, value -> value?.let { "$index:$it" } }
    println(destination)

    val notNullValues: Iterable<String?> = OneShot(listOf("a", null, "c"))
    println(notNullValues.mapNotNull { it })

    var exceptionCalls = 0
    try {
        val exceptionValues: Iterable<Int> = OneShot(listOf(1, 2, 3))
        exceptionValues.map {
            exceptionCalls += 1
            if (it == 2) throw IllegalStateException("stop")
            it
        }
    } catch (e: IllegalStateException) {
        println("exception:${exceptionCalls}")
    }
}
