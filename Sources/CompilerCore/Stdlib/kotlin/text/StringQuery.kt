package kotlin.text

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

// KSP-1399: keep the CharSequence single-family implementation on direct
// length/indexed-get dispatch so custom receivers retain Kotlin UTF-16 behavior.
public fun CharSequence.single(): Char {
    return when (length) {
        0 -> throw NoSuchElementException("Char sequence is empty.")
        1 -> this[0]
        else -> throw IllegalArgumentException("Char sequence has more than one element.")
    }
}

public inline fun CharSequence.single(predicate: (Char) -> Boolean): Char {
    var single: Char? = null
    var found = false
    var index = 0
    while (index < length) {
        val element = this[index]
        if (predicate(element)) {
            if (found) throw IllegalArgumentException("Char sequence contains more than one matching element.")
            single = element
            found = true
        }
        index++
    }
    if (!found) throw NoSuchElementException("Char sequence contains no character matching the predicate.")
    @Suppress("UNCHECKED_CAST")
    return single as Char
}

public fun CharSequence.singleOrNull(): Char? {
    return if (length == 1) this[0] else null
}

public inline fun CharSequence.singleOrNull(predicate: (Char) -> Boolean): Char? {
    var single: Char? = null
    var found = false
    var index = 0
    while (index < length) {
        val element = this[index]
        if (predicate(element)) {
            if (found) return null
            single = element
            found = true
        }
        index++
    }
    if (!found) return null
    return single
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
