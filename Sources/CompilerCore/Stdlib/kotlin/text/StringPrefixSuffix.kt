package kotlin.text

// KSP-404: prefix/suffix helpers migrated from Swift Runtime.
// startsWith / endsWith / removePrefix / removeSuffix / removeSurrounding.
//
// The flat String aggregate stores UTF-8 byte length, while Kotlin indexing is
// character-based, so `length`/`this[i]` walk past non-ASCII input. Character
// traversal goes through `toString().toList()` (see StringSearchReplace.kt).

/**
 * Returns `true` if this char sequence starts with the specified [prefix].
 */
public fun CharSequence.startsWith(prefix: CharSequence, ignoreCase: Boolean = false): Boolean {
    val selfChars = this.toString().toList()
    val prefixChars = prefix.toString().toList()
    return __kkRegionMatches(selfChars, 0, prefixChars, 0, prefixChars.size, ignoreCase)
}

/**
 * Returns `true` if a substring of this char sequence starting at the specified offset [startIndex]
 * starts with the specified [prefix].
 */
public fun CharSequence.startsWith(prefix: CharSequence, startIndex: Int, ignoreCase: Boolean = false): Boolean {
    val selfChars = this.toString().toList()
    val prefixChars = prefix.toString().toList()
    return __kkRegionMatches(selfChars, startIndex, prefixChars, 0, prefixChars.size, ignoreCase)
}

/**
 * Returns `true` if this char sequence starts with the specified character.
 */
public fun CharSequence.startsWith(char: Char, ignoreCase: Boolean = false): Boolean {
    val selfChars = this.toString().toList()
    return selfChars.size > 0 && __kkCharsEqual(selfChars[0], char, ignoreCase)
}

/**
 * Returns `true` if this char sequence ends with the specified [suffix].
 */
public fun CharSequence.endsWith(suffix: CharSequence, ignoreCase: Boolean = false): Boolean {
    val selfChars = this.toString().toList()
    val suffixChars = suffix.toString().toList()
    return __kkRegionMatches(selfChars, selfChars.size - suffixChars.size, suffixChars, 0, suffixChars.size, ignoreCase)
}

/**
 * Returns `true` if this char sequence ends with the specified character.
 */
public fun CharSequence.endsWith(char: Char, ignoreCase: Boolean = false): Boolean {
    val selfChars = this.toString().toList()
    return selfChars.size > 0 && __kkCharsEqual(selfChars[selfChars.size - 1], char, ignoreCase)
}

/**
 * If this string starts with the given [prefix], returns a copy of this string
 * with the prefix removed. Otherwise, returns this string.
 */
public fun String.removePrefix(prefix: CharSequence): String {
    if (startsWith(prefix)) {
        return this.substring(prefix.toString().toList().size)
    }
    return this
}

/**
 * If this string ends with the given [suffix], returns a copy of this string
 * with the suffix removed. Otherwise, returns this string.
 */
public fun String.removeSuffix(suffix: CharSequence): String {
    if (endsWith(suffix)) {
        val selfLength = this.toList().size
        return this.substring(0, selfLength - suffix.toString().toList().size)
    }
    return this
}

/**
 * When this string starts with the given [prefix] and ends with the given [suffix],
 * returns a copy of this string having both the given [prefix] and [suffix] removed.
 * Otherwise returns this string unchanged.
 */
public fun String.removeSurrounding(prefix: CharSequence, suffix: CharSequence): String {
    val selfLength = this.toList().size
    val prefixLength = prefix.toString().toList().size
    val suffixLength = suffix.toString().toList().size
    if (selfLength >= prefixLength + suffixLength && startsWith(prefix) && endsWith(suffix)) {
        return this.substring(prefixLength, selfLength - suffixLength)
    }
    return this
}

/**
 * When this string starts with and ends with the given [delimiter],
 * returns a copy of this string having the [delimiter] removed from both ends.
 * Otherwise returns this string unchanged.
 */
public fun String.removeSurrounding(delimiter: CharSequence): String = removeSurrounding(delimiter, delimiter)

// BUG-167: the String-receiver overloads above don't satisfy a call whose
// receiver is statically typed CharSequence (rather than a concrete String) —
// e.g. `fun f(value: CharSequence): String = value.removePrefix("foo")` —
// since Sema resolves member calls by the receiver's static type, not its
// runtime value. startsWith/endsWith above already have real
// CharSequence-receiver overloads for the same reason;
// removePrefix/removeSuffix/removeSurrounding were missing theirs. Unlike
// real Kotlin (whose CharSequence-receiver overloads return CharSequence),
// these return String: every CharSequence value this compiler's runtime
// actually produces is String-backed, and callers assign/return the result
// as String (matching the String-receiver overloads' signatures above), so
// a CharSequence return type here would just demand an extra, pointless
// `.toString()` at every call site for no behavioral difference.

/**
 * If this char sequence starts with the given [prefix], returns a copy of this char sequence
 * with the prefix removed. Otherwise, returns this char sequence.
 */
public fun CharSequence.removePrefix(prefix: CharSequence): String {
    if (startsWith(prefix)) {
        return this.toString().substring(prefix.toString().toList().size)
    }
    return this.toString()
}

/**
 * If this char sequence ends with the given [suffix], returns a copy of this char sequence
 * with the suffix removed. Otherwise, returns this char sequence.
 */
public fun CharSequence.removeSuffix(suffix: CharSequence): String {
    if (endsWith(suffix)) {
        val selfLength = this.toString().toList().size
        return this.toString().substring(0, selfLength - suffix.toString().toList().size)
    }
    return this.toString()
}

/**
 * When this char sequence starts with the given [prefix] and ends with the given [suffix],
 * returns a copy of this char sequence having both the given [prefix] and [suffix] removed.
 * Otherwise returns this char sequence unchanged.
 */
public fun CharSequence.removeSurrounding(prefix: CharSequence, suffix: CharSequence): String {
    val selfLength = this.toString().toList().size
    val prefixLength = prefix.toString().toList().size
    val suffixLength = suffix.toString().toList().size
    if (selfLength >= prefixLength + suffixLength && startsWith(prefix) && endsWith(suffix)) {
        return this.toString().substring(prefixLength, selfLength - suffixLength)
    }
    return this.toString()
}

/**
 * When this char sequence starts with and ends with the given [delimiter],
 * returns a copy of this char sequence having the [delimiter] removed from both ends.
 * Otherwise returns this char sequence unchanged.
 */
public fun CharSequence.removeSurrounding(delimiter: CharSequence): String = removeSurrounding(delimiter, delimiter)

// KSP-1393: CharSequence.removeRange is source-backed. Keep the two overloads
// separate from String.removeRange so static CharSequence receivers select the
// Kotlin 2.3.10 contract and preserve indexed CharSequence dispatch.
public fun CharSequence.removeRange(startIndex: Int, endIndex: Int): CharSequence {
    if (endIndex < startIndex) {
        throw IndexOutOfBoundsException("End index ($endIndex) is less than start index ($startIndex).")
    }

    if (endIndex == startIndex) {
        return this.subSequence(0, length)
    }

    // Match the Kotlin implementation's capacity calculation and length
    // evaluation order while avoiding the bundled StringBuilder bridge's
    // String-only cast for custom CharSequence receivers.
    val sb = StringBuilder(length - (endIndex - startIndex))
    val prefixLength = length
    appendCharSequenceRange(sb, this, 0, startIndex, prefixLength)
    val suffixEnd = length
    val suffixLength = length
    appendCharSequenceRange(sb, this, endIndex, suffixEnd, suffixLength)
    return sb
}

private fun appendCharSequenceRange(
    destination: StringBuilder,
    source: CharSequence,
    startIndex: Int,
    endIndex: Int,
    sourceLength: Int
): StringBuilder {
    if (startIndex < 0 || endIndex > sourceLength || startIndex > endIndex) {
        throw IndexOutOfBoundsException(
            "Range [$startIndex, $endIndex) out of bounds for length $sourceLength"
        )
    }

    var index = startIndex
    while (index < endIndex) {
        destination.append(source[index])
        index += 1
    }
    return destination
}

public fun CharSequence.removeRange(range: IntRange): CharSequence =
    removeRange(range.start, range.endInclusive + 1)
