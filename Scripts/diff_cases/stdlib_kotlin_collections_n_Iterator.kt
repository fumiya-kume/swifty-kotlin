class NullableIterator(private val values: List<String?>) : Iterator<String?> {
    private var index = 0

    override fun hasNext(): Boolean = index < values.size

    override fun next(): String? {
        if (!hasNext()) throw NoSuchElementException()
        val value = values[index]
        index++
        return value
    }
}

fun drain(iterator: Iterator<String?>): String {
    var result = ""
    while (iterator.hasNext()) {
        result += iterator.next() ?: "<null>"
    }
    return result
}

fun drainForIn(iterator: Iterator<String?>): String {
    var result = ""
    for (value in iterator) {
        result += value ?: "<null>"
    }
    return result
}

fun main() {
    val iterator: Iterator<String?> = NullableIterator(listOf("a", null, "b"))
    println(drain(iterator))

    val exhausted: Iterator<String?> = NullableIterator(emptyList())
    println(exhausted.hasNext())
    try {
        exhausted.next()
        println("missing")
    } catch (e: NoSuchElementException) {
        println("exhausted")
    }

    println(drainForIn(NullableIterator(listOf(null, "c"))))

    val sequence: Sequence<Int> = sequenceOf(1, 2, 3)
    val sequenceIterator: Iterator<Int> = sequence.iterator()
    println(sequenceIterator.next())
    println(sequenceIterator.hasNext())
}
