package kotlin.text

import kswiftk.internal.*
import kotlin.collections.CharIterator
import kotlin.collections.IndexedValue
import kotlin.collections.Iterable
import kotlin.collections.List
import kotlin.collections.MutableCollection
import kotlin.collections.MutableList
import kotlin.collections.MutableSet
import kotlin.collections.emptyList
import kotlin.collections.mutableListOf
import kotlin.collections.mutableSetOf
import kotlin.sequences.Sequence
import kotlin.sequences.emptySequence

// Collection conversions and iterator helpers migrated from the string runtime
// bridges. String is covered by these CharSequence extensions through the
// CharSequence implementation supplied by the compiler.

private class CharSequenceCharIterator(
    private val source: CharSequence
) : CharIterator() {
    private var index = 0

    override fun hasNext(): Boolean = index < source.length

    override fun nextChar(): Char {
        if (!hasNext()) throw NoSuchElementException()
        val result = source[index]
        index++
        return result
    }
}

public fun CharSequence.toList(): List<Char> {
    val result = mutableListOf<Char>()
    var index = 0
    val length = __kk_string_struct_get_length(this)
    while (index < length) {
        result.add(this[index])
        index++
    }
    return result
}

public fun CharSequence.toMutableList(): MutableList<Char> {
    val result = mutableListOf<Char>()
    var index = 0
    val length = __kk_string_struct_get_length(this)
    while (index < length) {
        result.add(this[index])
        index++
    }
    return result
}

public fun CharSequence.toCharArray(): CharArray {
    val length = __kk_string_struct_get_length(this)
    val result = CharArray(length)
    var index = 0
    while (index < length) {
        result[index] = this[index]
        index++
    }
    return result
}

@Suppress("UNCHECKED_CAST")
public fun CharSequence.toTypedArray(): Array<Char> {
    val length = __kk_string_struct_get_length(this)
    val result = arrayOfNulls<Char>(length)
    var index = 0
    while (index < length) {
        result[index] = this[index]
        index++
    }
    return result as Array<Char>
}

public fun <C : MutableCollection<in Char>> CharSequence.toCollection(destination: C): C {
    var index = 0
    val length = __kk_string_struct_get_length(this)
    while (index < length) {
        destination.add(this[index])
        index++
    }
    return destination
}

public fun CharSequence.toSortedSet(): MutableSet<Char> {
    val sorted = mutableListOf<Char>()
    var index = 0
    val length = __kk_string_struct_get_length(this)
    while (index < length) {
        val element = this[index]
        var insertAt = sorted.size
        while (insertAt > 0 && sorted[insertAt - 1].compareTo(element) > 0) {
            insertAt--
        }
        if (insertAt == sorted.size || sorted[insertAt] != element) {
            sorted.add(insertAt, element)
        }
        index++
    }

    val result = mutableSetOf<Char>()
    for (element in sorted) result.add(element)
    return result
}

public operator fun CharSequence.iterator(): CharIterator = CharSequenceCharIterator(this)

public fun CharSequence.asIterable(): Iterable<Char> {
    if (this is String && isEmpty()) return emptyList()
    val source = this
    return object : Iterable<Char> {
        override fun iterator(): Iterator<Char> = source.iterator()
    }
}

public fun CharSequence.asSequence(): Sequence<Char> {
    if (this is String && isEmpty()) return emptySequence<Char>()
    val source = this
    return object : Sequence<Char> {
        override fun iterator(): Iterator<Char> = source.iterator()
    }
}

public fun CharSequence.withIndex(): Iterable<IndexedValue<Char>> {
    val source = this
    return object : Iterable<IndexedValue<Char>> {
        override fun iterator(): Iterator<IndexedValue<Char>> {
            val iterator = source.iterator()
            return object : Iterator<IndexedValue<Char>> {
                private var index = 0

                override fun hasNext(): Boolean = iterator.hasNext()

                override fun next(): IndexedValue<Char> {
                    val result = IndexedValue(index, iterator.next())
                    index++
                    return result
                }
            }
        }
    }
}
