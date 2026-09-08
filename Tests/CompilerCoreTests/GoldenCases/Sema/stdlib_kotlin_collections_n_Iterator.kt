package golden.sema

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

fun consume(iterator: Iterator<String?>): String? =
    if (iterator.hasNext()) iterator.next() else null
