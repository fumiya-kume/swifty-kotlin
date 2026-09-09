// KSP-1026: AbstractCollection's concrete member implementations are
// source-backed. Exercise rendering and both protected toArray overloads.

import kotlin.collections.AbstractCollection
import kotlin.collections.Iterator

private class ProbeIterator(private val values: Array<Any?>) : Iterator<Any?> {
    private var index = 0

    override fun hasNext(): Boolean = index < values.size

    override fun next(): Any? {
        val value = values[index]
        index += 1
        return value
    }
}

class ProbeCollection : AbstractCollection<Any?>() {
    private val values = arrayOf<Any?>(1, "two", null)

    override val size: Int
        get() = values.size

    override fun iterator(): Iterator<Any?> = ProbeIterator(values)

    fun objectArray(): Array<Any?> = toArray()

    fun copyInto(array: Array<Any?>): Array<Any?> = toArray(array)
}

class SelfCollection : AbstractCollection<Any?>() {
    override val size: Int
        get() = 1

    override fun iterator(): Iterator<Any?> = ProbeIterator(arrayOf<Any?>(this))
}

fun main() {
    val collection = ProbeCollection()
    println(collection.toString())
    println(collection.objectArray().contentToString())

    val exact = arrayOf<Any?>(0, 0, 0)
    val exactResult = collection.copyInto(exact)
    println(exactResult.contentToString())
    println(exactResult === exact)

    val large = arrayOf<Any?>(0, 0, 0, null)
    val largeResult = collection.copyInto(large)
    println(largeResult.contentToString())
    println(largeResult === large)

    val short = arrayOf<Any?>(0)
    val expandedResult = collection.copyInto(short)
    println(expandedResult.contentToString())
    println(expandedResult === short)

    println(SelfCollection().toString())
}
