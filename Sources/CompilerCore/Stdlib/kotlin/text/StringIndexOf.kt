package kotlin.text

// KSP-408: contains/indexOf family migrated from Swift Runtime
// (RuntimeStringStdlib.swift's contains functions + RuntimeStringSearch.swift).
//
// Character traversal goes through toString().toList() (see StringSearchReplace.kt /
// StringPrefixSuffix.kt): the flat String aggregate's length/get(i) are unreliable for
// non-ASCII input on a CharSequence-typed receiver, so every function here normalizes
// to a concrete List<Char> before scanning.
//
// ignoreCase=false and ignoreCase=true diverge on kotlinc for one specific shape: an
// empty String needle combined with an out-of-range startIndex. ignoreCase=false mirrors
// the JVM native fast path (clamps startIndex into range and still reports a trivial
// match); ignoreCase=true mirrors the generic loop-based path (an out-of-range startIndex
// yields an empty scan range, so no match is reported). Verified against kotlinc 2.4.10;
// see Scripts/diff_cases/string_lookup_ignorecase.kt and string_contains.kt.
//
// `lastIndexOf`'s upstream default startIndex is `lastIndex` (= length - 1). Rather than
// use it as a default-parameter expression (unreliable on a CharSequence-typed receiver;
// this compiler cannot resolve the omitted-argument overload when the default expression
// is a non-literal computed value such as Int.MIN_VALUE), the backward-search functions
// below split into a no-startIndex overload and an explicit-startIndex overload sharing a
// private impl, so the only default-parameter values needed anywhere in this file are
// plain literals (0, false).

private fun charEqualsAt(selfChars: List<Char>, pos: Int, target: Char, ignoreCase: Boolean): Boolean {
    if (pos < 0 || pos >= selfChars.size) return false
    return __kkCharsEqual(selfChars[pos], target, ignoreCase)
}

private fun charArrayMatchesAt(selfChars: List<Char>, pos: Int, chars: CharArray, ignoreCase: Boolean): Boolean {
    if (pos < 0 || pos >= selfChars.size) return false
    var i = 0
    while (i < chars.size) {
        if (__kkCharsEqual(selfChars[pos], chars[i], ignoreCase)) return true
        i++
    }
    return false
}

// Returns the index of the first (in iteration order) of `needles` that matches at `pos`,
// or -1 if none does. Deliberately returns an Int rather than the matched String itself:
// `String?` comparisons against `null` are unreliable in this compiler when the string
// value is empty (KSWIFTK-INTERNAL-0002 — an empty String and `null` are indistinguishable
// under `==`/`!=`), which previously made empty-needle matches silently disappear here.
private fun stringCollectionMatchIndexAt(
    selfChars: List<Char>,
    pos: Int,
    needles: List<String>,
    ignoreCase: Boolean
): Int {
    var i = 0
    while (i < needles.size) {
        val needleChars = needles[i].toList()
        if (__kkRegionMatches(selfChars, pos, needleChars, 0, needleChars.size, ignoreCase)) return i
        i++
    }
    return -1
}

// startIndex clamp for forward scans (indexOf / indexOfAny / findAnyOf family).
private fun forwardSearchStart(startIndex: Int, ignoreCase: Boolean, size: Int): Int {
    val lowerClamped = if (startIndex < 0) 0 else startIndex
    if (ignoreCase) return lowerClamped
    return if (lowerClamped > size) size else lowerClamped
}

// startIndex clamp for backward scans (lastIndexOf / lastIndexOfAny / findLastAnyOf
// family). `startIndex == null` means "use the default" (upstream `lastIndex`).
// Returns a negative value when the scan range is empty; callers must check.
private fun backwardSearchStart(startIndex: Int?, ignoreCase: Boolean, size: Int): Int {
    val resolved = startIndex ?: (size - 1)
    if (ignoreCase) {
        val upperBound = size - 1
        return if (resolved < upperBound) resolved else upperBound
    }
    if (resolved < 0) return -1
    return if (resolved < size) resolved else size
}

/**
 * Returns `true` if this char sequence contains the specified [other] sequence of characters as a substring.
 */
// Split into two overloads (rather than one function with a defaulted ignoreCase) because
// this compiler's `in`-operator resolution (ExprTypeChecker.inferContainsCallBinding) only
// recognizes `operator fun contains` candidates with exactly one formal parameter; it does
// not fill in defaulted trailing parameters the way normal call resolution does. Matches the
// arity split the previous synthetic stub used for the same reason.
public operator fun CharSequence.contains(other: CharSequence): Boolean =
    contains(other, ignoreCase = false)

private fun charSequenceContains(
    self: CharSequence,
    other: CharSequence,
    ignoreCase: Boolean
): Boolean {
    // String's flat representation does not expose reliable Kotlin character
    // indices for non-ASCII input. Keep String on the normalized list path,
    // while custom CharSequence implementations are read through length/get.
    val selfChars = if (self is String) self.toString().toList() else null
    val otherChars = if (other is String) other.toString().toList() else null
    val selfLength = selfChars?.size ?: self.length
    val otherLength = otherChars?.size ?: other.length
    if (otherLength == 0) return true
    if (otherLength > selfLength) return false

    var start = 0
    val lastStart = selfLength - otherLength
    while (start <= lastStart) {
        var offset = 0
        var matched = true
        while (offset < otherLength) {
            var equal = false
            if (selfChars != null) {
                if (otherChars != null) {
                    equal = __kkCharsEqual(selfChars[start + offset], otherChars[offset], ignoreCase)
                } else {
                    equal = __kkCharsEqual(selfChars[start + offset], other[offset], ignoreCase)
                }
            } else {
                if (otherChars != null) {
                    equal = __kkCharsEqual(self[start + offset], otherChars[offset], ignoreCase)
                } else {
                    equal = __kkCharsEqual(self[start + offset], other[offset], ignoreCase)
                }
            }
            if (!equal) {
                matched = false
                break
            }
            offset++
        }
        if (matched) return true
        start++
    }
    return false
}

public fun CharSequence.contains(other: CharSequence, ignoreCase: Boolean): Boolean =
    charSequenceContains(this, other, ignoreCase)

/**
 * Returns `true` if this char sequence contains the specified [char].
 */
public operator fun CharSequence.contains(char: Char): Boolean =
    contains(char, ignoreCase = false)

public fun CharSequence.contains(char: Char, ignoreCase: Boolean): Boolean {
    // Preserve the existing String search implementation, including its
    // UTF-16 normalization, while custom receivers use indexed access.
    if (this is String) return indexOf(char, 0, ignoreCase) >= 0
    var index = 0
    val length = this.length
    while (index < length) {
        if (__kkCharsEqual(this[index], char, ignoreCase)) return true
        index++
    }
    return false
}

/**
 * Returns the first index of [string] in this char sequence starting from [startIndex], or -1 if not found.
 */
public fun CharSequence.indexOf(string: String, startIndex: Int = 0, ignoreCase: Boolean = false): Int {
    val selfChars = this.toString().toList()
    val needleChars = string.toList()
    var pos = forwardSearchStart(startIndex, ignoreCase, selfChars.size)
    while (pos <= selfChars.size) {
        if (__kkRegionMatches(selfChars, pos, needleChars, 0, needleChars.size, ignoreCase)) return pos
        pos++
    }
    return -1
}

/**
 * Returns the first index of [char] in this char sequence starting from [startIndex], or -1 if not found.
 */
public fun CharSequence.indexOf(char: Char, startIndex: Int = 0, ignoreCase: Boolean = false): Int {
    val selfChars = this.toString().toList()
    var pos = forwardSearchStart(startIndex, ignoreCase, selfChars.size)
    while (pos <= selfChars.size) {
        if (charEqualsAt(selfChars, pos, char, ignoreCase)) return pos
        pos++
    }
    return -1
}

private fun lastIndexOfStringImpl(selfChars: List<Char>, needleChars: List<Char>, startIndex: Int?, ignoreCase: Boolean): Int {
    var pos = backwardSearchStart(startIndex, ignoreCase, selfChars.size)
    while (pos >= 0) {
        if (__kkRegionMatches(selfChars, pos, needleChars, 0, needleChars.size, ignoreCase)) return pos
        pos--
    }
    return -1
}

/**
 * Returns the last index of [string] in this char sequence, searching backward from the end, or -1 if not found.
 */
public fun CharSequence.lastIndexOf(string: String, ignoreCase: Boolean = false): Int =
    lastIndexOfStringImpl(this.toString().toList(), string.toList(), null, ignoreCase)

/**
 * Returns the last index of [string] in this char sequence, searching backward starting at [startIndex],
 * or -1 if not found.
 */
public fun CharSequence.lastIndexOf(string: String, startIndex: Int, ignoreCase: Boolean = false): Int =
    lastIndexOfStringImpl(this.toString().toList(), string.toList(), startIndex, ignoreCase)

private fun lastIndexOfCharImpl(selfChars: List<Char>, char: Char, startIndex: Int?, ignoreCase: Boolean): Int {
    var pos = backwardSearchStart(startIndex, ignoreCase, selfChars.size)
    while (pos >= 0) {
        if (charEqualsAt(selfChars, pos, char, ignoreCase)) return pos
        pos--
    }
    return -1
}

/**
 * Returns the last index of [char] in this char sequence, searching backward from the end, or -1 if not found.
 */
public fun CharSequence.lastIndexOf(char: Char, ignoreCase: Boolean = false): Int =
    lastIndexOfCharImpl(this.toString().toList(), char, null, ignoreCase)

/**
 * Returns the last index of [char] in this char sequence, searching backward starting at [startIndex],
 * or -1 if not found.
 */
public fun CharSequence.lastIndexOf(char: Char, startIndex: Int, ignoreCase: Boolean = false): Int =
    lastIndexOfCharImpl(this.toString().toList(), char, startIndex, ignoreCase)

/**
 * Returns the index of the first occurrence of any of the specified [chars] in this char sequence,
 * starting from [startIndex], or -1 if none of [chars] is found.
 */
public fun CharSequence.indexOfAny(chars: CharArray, startIndex: Int = 0, ignoreCase: Boolean = false): Int {
    val selfChars = this.toString().toList()
    var pos = forwardSearchStart(startIndex, ignoreCase, selfChars.size)
    while (pos <= selfChars.size) {
        if (charArrayMatchesAt(selfChars, pos, chars, ignoreCase)) return pos
        pos++
    }
    return -1
}

/**
 * Returns the index of the first occurrence of any of the specified [strings] in this char sequence,
 * starting from [startIndex], or -1 if none of [strings] is found.
 */
public fun CharSequence.indexOfAny(strings: Collection<String>, startIndex: Int = 0, ignoreCase: Boolean = false): Int {
    val selfChars = this.toString().toList()
    val needlesList = strings.toList()
    var pos = forwardSearchStart(startIndex, ignoreCase, selfChars.size)
    while (pos <= selfChars.size) {
        if (stringCollectionMatchIndexAt(selfChars, pos, needlesList, ignoreCase) >= 0) return pos
        pos++
    }
    return -1
}

private fun lastIndexOfAnyCharsImpl(selfChars: List<Char>, chars: CharArray, startIndex: Int?, ignoreCase: Boolean): Int {
    var pos = backwardSearchStart(startIndex, ignoreCase, selfChars.size)
    while (pos >= 0) {
        if (charArrayMatchesAt(selfChars, pos, chars, ignoreCase)) return pos
        pos--
    }
    return -1
}

/**
 * Returns the index of the last occurrence of any of the specified [chars] in this char sequence,
 * searching backward from the end, or -1 if none found.
 */
public fun CharSequence.lastIndexOfAny(chars: CharArray, ignoreCase: Boolean = false): Int =
    lastIndexOfAnyCharsImpl(this.toString().toList(), chars, null, ignoreCase)

/**
 * Returns the index of the last occurrence of any of the specified [chars] in this char sequence,
 * searching backward starting at [startIndex], or -1 if none found.
 */
public fun CharSequence.lastIndexOfAny(chars: CharArray, startIndex: Int, ignoreCase: Boolean = false): Int =
    lastIndexOfAnyCharsImpl(this.toString().toList(), chars, startIndex, ignoreCase)

private fun lastIndexOfAnyStringsImpl(
    selfChars: List<Char>,
    strings: Collection<String>,
    startIndex: Int?,
    ignoreCase: Boolean
): Int {
    val needlesList = strings.toList()
    var pos = backwardSearchStart(startIndex, ignoreCase, selfChars.size)
    while (pos >= 0) {
        if (stringCollectionMatchIndexAt(selfChars, pos, needlesList, ignoreCase) >= 0) return pos
        pos--
    }
    return -1
}

/**
 * Returns the index of the last occurrence of any of the specified [strings] in this char sequence,
 * searching backward from the end, or -1 if none found.
 */
public fun CharSequence.lastIndexOfAny(strings: Collection<String>, ignoreCase: Boolean = false): Int =
    lastIndexOfAnyStringsImpl(this.toString().toList(), strings, null, ignoreCase)

/**
 * Returns the index of the last occurrence of any of the specified [strings] in this char sequence,
 * searching backward starting at [startIndex], or -1 if none found.
 */
public fun CharSequence.lastIndexOfAny(strings: Collection<String>, startIndex: Int, ignoreCase: Boolean = false): Int =
    lastIndexOfAnyStringsImpl(this.toString().toList(), strings, startIndex, ignoreCase)

/**
 * Finds the first occurrence of any of the specified [strings] in this char sequence, starting from
 * [startIndex]. Returns the index and the matching string as a [Pair], or `null` if none is found.
 */
public fun CharSequence.findAnyOf(
    strings: Collection<String>,
    startIndex: Int = 0,
    ignoreCase: Boolean = false
): Pair<Int, String>? {
    val selfChars = this.toString().toList()
    val needlesList = strings.toList()
    var pos = forwardSearchStart(startIndex, ignoreCase, selfChars.size)
    while (pos <= selfChars.size) {
        val idx = stringCollectionMatchIndexAt(selfChars, pos, needlesList, ignoreCase)
        if (idx >= 0) return Pair(pos, needlesList[idx])
        pos++
    }
    return null
}

private fun findLastAnyOfImpl(
    selfChars: List<Char>,
    strings: Collection<String>,
    startIndex: Int?,
    ignoreCase: Boolean
): Pair<Int, String>? {
    val needlesList = strings.toList()
    var pos = backwardSearchStart(startIndex, ignoreCase, selfChars.size)
    while (pos >= 0) {
        val idx = stringCollectionMatchIndexAt(selfChars, pos, needlesList, ignoreCase)
        if (idx >= 0) return Pair(pos, needlesList[idx])
        pos--
    }
    return null
}

/**
 * Finds the last occurrence of any of the specified [strings] in this char sequence, searching backward
 * from the end. Returns the index and the matching string as a [Pair], or `null` if none is found.
 */
public fun CharSequence.findLastAnyOf(strings: Collection<String>, ignoreCase: Boolean = false): Pair<Int, String>? =
    findLastAnyOfImpl(this.toString().toList(), strings, null, ignoreCase)

/**
 * Finds the last occurrence of any of the specified [strings] in this char sequence, searching backward
 * starting at [startIndex]. Returns the index and the matching string as a [Pair], or `null` if none is found.
 */
public fun CharSequence.findLastAnyOf(strings: Collection<String>, startIndex: Int, ignoreCase: Boolean = false): Pair<Int, String>? =
    findLastAnyOfImpl(this.toString().toList(), strings, startIndex, ignoreCase)

/**
 * Returns the index of the first character matching the given [predicate], or -1 if none matches.
 */
public inline fun CharSequence.indexOfFirst(predicate: (Char) -> Boolean): Int {
    val selfChars = this.toString().toList()
    var i = 0
    while (i < selfChars.size) {
        if (predicate(selfChars[i])) return i
        i++
    }
    return -1
}

/**
 * Returns the index of the last character matching the given [predicate], or -1 if none matches.
 */
public inline fun CharSequence.indexOfLast(predicate: (Char) -> Boolean): Int {
    val selfChars = this.toString().toList()
    var i = selfChars.size - 1
    while (i >= 0) {
        if (predicate(selfChars[i])) return i
        i--
    }
    return -1
}
