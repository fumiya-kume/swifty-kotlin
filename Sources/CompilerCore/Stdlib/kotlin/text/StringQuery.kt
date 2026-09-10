package kotlin.text

import kotlin.contracts.ExperimentalContracts
import kotlin.contracts.InvocationKind
import kotlin.contracts.contract

// KSP-402
// String query helpers migrated from Swift runtime entry points.

public fun String.first(): Char {
    return this.__kk_string_first()
}

public fun String.first(predicate: (Char) -> Boolean): Char {
    var foundIndex = -1
    var i = 0
    val sz = length
    while (i < sz && foundIndex < 0) {
        if (predicate(this[i])) {
            foundIndex = i
        }
        i += 1
    }
    if (foundIndex >= 0) return this[foundIndex]
    throw NoSuchElementException("Char sequence contains no character matching the predicate.")
}

public fun String.firstOrNull(): Char? {
    return this.__kk_string_firstOrNull()
}

public fun String.firstOrNull(predicate: (Char) -> Boolean): Char? {
    var foundIndex = -1
    var i = 0
    val sz = length
    while (i < sz && foundIndex < 0) {
        if (predicate(this[i])) {
            foundIndex = i
        }
        i += 1
    }
    if (foundIndex >= 0) return this[foundIndex]
    return null
}

public fun String.last(): Char {
    return this.__kk_string_last()
}

public fun String.last(predicate: (Char) -> Boolean): Char {
    var foundIndex = -1
    var i = length - 1
    while (i >= 0 && foundIndex < 0) {
        if (predicate(this[i])) {
            foundIndex = i
        }
        i -= 1
    }
    if (foundIndex >= 0) return this[foundIndex]
    throw NoSuchElementException("Char sequence contains no character matching the predicate.")
}

public fun String.lastOrNull(): Char? {
    return this.__kk_string_lastOrNull()
}

public fun String.lastOrNull(predicate: (Char) -> Boolean): Char? {
    var foundIndex = -1
    var i = length - 1
    while (i >= 0 && foundIndex < 0) {
        if (predicate(this[i])) {
            foundIndex = i
        }
        i -= 1
    }
    if (foundIndex >= 0) return this[foundIndex]
    return null
}

// KSP-1384: CharSequence last-family APIs are source-backed. Keep the
// String-specific bridge overloads above because unrelated String callers
// still use their runtime-backed no-predicate implementations.
public fun CharSequence.last(): Char {
    if (isEmpty())
        throw NoSuchElementException("Char sequence is empty.")
    return this[length - 1]
}

public inline fun CharSequence.last(predicate: (Char) -> Boolean): Char {
    var index = length - 1
    while (index >= 0) {
        val element = this[index]
        if (predicate(element)) return element
        index--
    }
    throw NoSuchElementException("Char sequence contains no character matching the predicate.")
}

public val CharSequence.lastIndex: Int
    get() = this.length - 1

public fun CharSequence.lastOrNull(): Char? {
    return if (isEmpty()) null else this[length - 1]
}

public inline fun CharSequence.lastOrNull(predicate: (Char) -> Boolean): Char? {
    var index = length - 1
    while (index >= 0) {
        val element = this[index]
        if (predicate(element)) return element
        index--
    }
    return null
}

public fun String.single(): Char {
    return this.__kk_string_single()
}

public fun String.single(predicate: (Char) -> Boolean): Char {
    var matchIndex = -1
    var hasMultipleMatches = false
    var i = 0
    val sz = length
    while (i < sz) {
        if (predicate(this[i])) {
            if (matchIndex >= 0) {
                hasMultipleMatches = true
            } else {
                matchIndex = i
            }
        }
        i += 1
    }
    if (hasMultipleMatches) {
        throw IllegalArgumentException("Char sequence contains more than one matching element.")
    }
    if (matchIndex >= 0) return this[matchIndex]
    throw NoSuchElementException("Char sequence contains no character matching the predicate.")
}

public fun String.singleOrNull(): Char? {
    return this.__kk_string_singleOrNull()
}

public fun String.singleOrNull(predicate: (Char) -> Boolean): Char? {
    var matchIndex = -1
    var hasMultipleMatches = false
    var i = 0
    val sz = length
    while (i < sz) {
        if (predicate(this[i])) {
            if (matchIndex >= 0) {
                hasMultipleMatches = true
            } else {
                matchIndex = i
            }
        }
        i += 1
    }
    if (!hasMultipleMatches && matchIndex >= 0) return this[matchIndex]
    return null
}

public fun String.getOrNull(index: Int): Char? {
    return this.__kk_string_getOrNull(index)
}

@kotlin.internal.InlineOnly
@OptIn(ExperimentalContracts::class)
public inline fun CharSequence.getOrElse(index: Int, defaultValue: (Int) -> Char): Char {
    contract { callsInPlace(defaultValue, InvocationKind.AT_MOST_ONCE) }
    return if (index >= 0 && index < length) get(index) else defaultValue(index)
}

public fun CharSequence.getOrNull(index: Int): Char? =
    if (index >= 0 && index < length) get(index) else null
