import kotlin.collections.AbstractCollection
import kotlin.collections.Iterator

private class ProbeIterator(private val values: Array<String?>) : Iterator<String?> {
    private var index = 0

    override fun hasNext(): Boolean = index < values.size

    override fun next(): String? {
        val value = values[index]
        index += 1
        return value
    }
}

class ProbeCollection : AbstractCollection<String?>() {
    private val values = arrayOf<String?>("one", null)

    override val size: Int
        get() = values.size

    override fun iterator(): Iterator<String?> = ProbeIterator(values)

    fun objectArray(): Array<Any?> = toArray()

    fun copyInto(array: Array<Any?>): Array<Any?> = toArray(array)
}

fun inspect(collection: ProbeCollection): String {
    val rendered = collection.toString()
    val objectArray = collection.objectArray()
    val typedArray = collection.copyInto(arrayOf<Any?>(null, null))
    return "$rendered:${objectArray.size}:${typedArray.size}"
}
