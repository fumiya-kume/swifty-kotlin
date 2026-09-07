package kotlin.collections

import kotlin.comparisons.compareValues
import kotlin.internal.KsSymbolName
import kotlin.random.Random

// MIGRATION-COL-006
// List sorting/comparison HOFs migrated to Kotlin source.
// Migration source:
//   Sources/Runtime/RuntimeCollectionHOF.swift
//   Sources/Runtime/RuntimeCollectionHOFMaxMin.swift
//
// These inline implementations are used by bundled List call sites. Legacy
// synthetic ABI registrations remain only as compatibility fallbacks outside
// the bundled source path.

public inline fun <T : Comparable<T>> List<T>.sorted(): List<T> {
    val result = mutableListOf<T>()
    var i = 0
    while (i < size) {
        val element = this[i]
        var insertAt = result.size
        while (insertAt > 0 && result[insertAt - 1].compareTo(element) > 0) {
            insertAt--
        }
        result.add(insertAt, element)
        i++
    }
    return result
}

public inline fun <T, R : Comparable<R>> List<T>.sortedBy(selector: (T) -> R): List<T> {
    val result = mutableListOf<T>()
    val keys = mutableListOf<R>()
    var i = 0
    while (i < size) {
        val element = this[i]
        val key = selector(element)
        var insertAt = keys.size
        while (insertAt > 0 && keys[insertAt - 1].compareTo(key) > 0) {
            insertAt--
        }
        keys.add(insertAt, key)
        result.add(insertAt, element)
        i++
    }
    return result
}

public inline fun <T, R : Comparable<R>> List<T>.sortedByDescending(selector: (T) -> R?): List<T> {
    val result = mutableListOf<T>()
    val keys = mutableListOf<R?>()
    var i = 0
    while (i < size) {
        val element = this[i]
        val key = selector(element)
        var insertAt = keys.size
        while (insertAt > 0 && compareValues(keys[insertAt - 1], key) < 0) {
            insertAt--
        }
        keys.add(insertAt, key)
        result.add(insertAt, element)
        i++
    }
    return result
}

public inline fun <T> List<T>.sortedWith(comparator: Comparator<in T>): List<T> {
    val result = mutableListOf<T>()
    var i = 0
    while (i < size) {
        val element = this[i]
        var insertAt = result.size
        while (insertAt > 0 && comparator.compare(result[insertAt - 1], element) > 0) {
            insertAt--
        }
        result.add(insertAt, element)
        i++
    }
    return result
}

public inline fun <T : Comparable<T>> List<T>.sortedDescending(): List<T> {
    val result = mutableListOf<T>()
    var i = 0
    while (i < size) {
        val element = this[i]
        var insertAt = result.size
        while (insertAt > 0 && result[insertAt - 1].compareTo(element) < 0) {
            insertAt--
        }
        result.add(insertAt, element)
        i++
    }
    return result
}

public inline fun <T : Comparable<T>> MutableList<T>.sort() {
    if (size <= 1) return
    var i = 0
    while (i < size - 1) {
        var j = 0
        while (j < size - i - 1) {
            if (this[j + 1] < this[j]) {
                val tmp = this[j]
                this[j] = this[j + 1]
                this[j + 1] = tmp
            }
            j++
        }
        i++
    }
}

public inline fun <T : Comparable<T>> MutableList<T>.sortDescending() {
    if (size <= 1) return
    var i = 0
    while (i < size - 1) {
        var j = 0
        while (j < size - i - 1) {
            if (this[j + 1] > this[j]) {
                val tmp = this[j]
                this[j] = this[j + 1]
                this[j + 1] = tmp
            }
            j++
        }
        i++
    }
}

public inline fun <T, R : Comparable<R>> MutableList<T>.sortBy(selector: (T) -> R) {
    if (size <= 1) return
    var i = 0
    while (i < size - 1) {
        var j = 0
        while (j < size - i - 1) {
            if (selector(this[j + 1]) < selector(this[j])) {
                val tmp = this[j]
                this[j] = this[j + 1]
                this[j + 1] = tmp
            }
            j++
        }
        i++
    }
}

public inline fun <T, R : Comparable<R>> MutableList<T>.sortByDescending(selector: (T) -> R) {
    if (size <= 1) return
    var i = 0
    while (i < size - 1) {
        var j = 0
        while (j < size - i - 1) {
            if (selector(this[j + 1]) > selector(this[j])) {
                val tmp = this[j]
                this[j] = this[j + 1]
                this[j + 1] = tmp
            }
            j++
        }
        i++
    }
}

public inline fun <T> MutableList<T>.sortWith(comparator: Comparator<in T>) {
    if (size <= 1) return
    var i = 0
    while (i < size - 1) {
        var j = 0
        while (j < size - i - 1) {
            if (comparator.compare(this[j + 1], this[j]) < 0) {
                val tmp = this[j]
                this[j] = this[j + 1]
                this[j + 1] = tmp
            }
            j++
        }
        i++
    }
}

public inline fun <T> List<T>.sortedWith(comparison: (T, T) -> Int): List<T> {
    val result = mutableListOf<T>()
    var i = 0
    while (i < size) {
        val element = this[i]
        var insertAt = result.size
        while (insertAt > 0 && comparison(result[insertAt - 1], element) > 0) {
            insertAt--
        }
        result.add(insertAt, element)
        i++
    }
    return result
}

public inline fun <T> MutableList<T>.sortWith(comparison: (T, T) -> Int) {
    if (size <= 1) return
    var i = 0
    while (i < size - 1) {
        var j = 0
        while (j < size - i - 1) {
            if (comparison(this[j + 1], this[j]) < 0) {
                val tmp = this[j]
                this[j] = this[j + 1]
                this[j + 1] = tmp
            }
            j++
        }
        i++
    }
}

public fun <T> List<T>.shuffled(): List<T> = shuffled(Random.Default)

public fun <T> List<T>.shuffled(random: Random): List<T> {
    val result = mutableListOf<T>()
    var copyIndex = 0
    while (copyIndex < size) {
        result.add(this[copyIndex])
        copyIndex++
    }

    var i = result.size - 1
    while (i > 0) {
        val j = random.nextInt(i + 1)
        val tmp = result[i]
        result[i] = result[j]
        result[j] = tmp
        i--
    }
    return result
}

// KSP-1021: MutableList collection APIs migrated to Kotlin source.
// The existing runtime reversed-view bridge is intentionally shared with the
// read-only List.asReversed implementation in ListCollectionOps.kt.
@KsSymbolName("__kk_list_as_reversed")
private external fun <T> __kk_mutable_list_as_reversed(list: MutableList<T>): MutableList<T>

public fun <T> MutableList<T>.asReversed(): MutableList<T> {
    return __kk_mutable_list_as_reversed(this)
}

@Deprecated("Use removeAt(index) instead.", ReplaceWith("removeAt(index)"), level = DeprecationLevel.ERROR)
public inline fun <T> MutableList<T>.remove(index: Int): T {
    return removeAt(index)
}

@SinceKotlin("1.4")
@IgnorableReturnValue
public fun <T> MutableList<T>.removeFirst(): T {
    if (isEmpty()) throw NoSuchElementException("List is empty.")
    return removeAt(0)
}

@SinceKotlin("1.4")
@IgnorableReturnValue
public fun <T> MutableList<T>.removeFirstOrNull(): T? {
    if (isEmpty()) return null
    return removeAt(0)
}

@SinceKotlin("1.4")
@IgnorableReturnValue
public fun <T> MutableList<T>.removeLast(): T {
    if (isEmpty()) throw NoSuchElementException("List is empty.")
    return removeAt(size - 1)
}

@SinceKotlin("1.4")
@IgnorableReturnValue
public fun <T> MutableList<T>.removeLastOrNull(): T? {
    if (isEmpty()) return null
    return removeAt(size - 1)
}

@IgnorableReturnValue
public fun <T> MutableList<T>.removeAll(predicate: (T) -> Boolean): Boolean {
    return filterInPlace(predicate, true)
}

@IgnorableReturnValue
public fun <T> MutableList<T>.retainAll(predicate: (T) -> Boolean): Boolean {
    return filterInPlace(predicate, false)
}

private fun <T> MutableList<T>.filterInPlace(
    predicate: (T) -> Boolean,
    predicateResultToRemove: Boolean
): Boolean {
    val originalSize = size
    var writeIndex = 0
    var readIndex = 0
    while (readIndex < originalSize) {
        val element = this[readIndex]
        if (predicate(element) != predicateResultToRemove) {
            if (writeIndex != readIndex) this[writeIndex] = element
            writeIndex++
        }
        readIndex++
    }

    if (writeIndex >= size) return false
    var removeIndex = originalSize - 1
    while (removeIndex >= writeIndex) {
        removeAt(removeIndex)
        removeIndex--
    }
    return true
}

public fun <T> MutableList<T>.reverse() {
    var left = 0
    var right = size - 1
    while (left < right) {
        val temporary = this[left]
        this[left] = this[right]
        this[right] = temporary
        left++
        right--
    }
}

@SinceKotlin("1.2")
public fun <T> MutableList<T>.shuffle() {
    shuffle(Random.Default)
}

@KsSymbolName("__kk_random_nextInt_rangeObject")
private external fun __kk_mutable_list_random_nextInt(random: Random, range: IntRange): Int

@SinceKotlin("1.3")
public fun <T> MutableList<T>.shuffle(random: Random) {
    var i = size - 1
    while (i > 0) {
        val j = if (random === Random.Default) {
            // Random.Default is represented by the runtime singleton handle,
            // so use the bridge instead of virtual dispatch on that handle.
            __kk_mutable_list_random_nextInt(random, 0..i)
        } else {
            random.nextInt(i + 1)
        }
        val temporary = this[i]
        this[i] = this[j]
        this[j] = temporary
        i--
    }
}
