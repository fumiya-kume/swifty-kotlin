package kotlin.text

// KSP-406: substring / subSequence / slice / removeRange / replaceRange.
// Character indices traverse toString().toList() because Kotlin String and
// CharSequence lengths are measured in UTF-16 code units.

private fun buildStringFromCharRange(chars: List<Char>, startIndex: Int, endIndex: Int): String {
    val sb = StringBuilder()
    var i = startIndex
    while (i < endIndex) {
        sb.append(chars[i])
        i++
    }
    return sb.toString()
}

public fun String.substring(startIndex: Int): String {
    val chars = this.toString().toList()
    val length = chars.size
    if (startIndex < 0 || startIndex > length) {
        throw IndexOutOfBoundsException("begin $startIndex, end $length, length $length")
    }
    return buildStringFromCharRange(chars, startIndex, length)
}

public fun String.substring(startIndex: Int, endIndex: Int): String {
    val chars = this.toString().toList()
    val length = chars.size
    if (startIndex < 0 || endIndex > length || startIndex > endIndex) {
        throw IndexOutOfBoundsException("begin $startIndex, end $endIndex, length $length")
    }
    return buildStringFromCharRange(chars, startIndex, endIndex)
}

@kotlin.internal.InlineOnly
public inline fun CharSequence.substring(startIndex: Int, endIndex: Int = length): String =
    this.subSequence(startIndex, endIndex).toString()

public fun CharSequence.substring(range: IntRange): String =
    this.subSequence(range.start, range.endInclusive + 1).toString()

@Deprecated(
    "Use substring(startIndex, endIndex) instead.",
    ReplaceWith("substring(startIndex, endIndex)")
)
public fun String.subSequence(startIndex: Int, endIndex: Int): String =
    this.substring(startIndex, endIndex)

// BUG-152: members reached through a value statically typed as `CharSequence`.
public fun CharSequence.subSequence(startIndex: Int, endIndex: Int): CharSequence =
    this.toString().substring(startIndex, endIndex)

public fun CharSequence.subSequence(range: IntRange): CharSequence =
    this.subSequence(range.start, range.endInclusive + 1)

public fun String.slice(indices: IntRange): String {
    if (indices.isEmpty()) return ""
    return this.substring(indices.first, indices.last + 1)
}

public fun String.slice(indices: Iterable<Int>): String {
    val chars = this.toString().toList()
    val length = chars.size
    val sb = StringBuilder()
    for (index in indices) {
        if (index < 0 || index >= length) {
            throw IndexOutOfBoundsException("index $index out of range [0, $length)")
        }
        sb.append(chars[index])
    }
    return sb.toString()
}

public fun String.removeRange(startIndex: Int, endIndex: Int): String {
    val chars = this.toString().toList()
    val length = chars.size
    if (startIndex < 0 || startIndex > length || endIndex < 0 || endIndex > length || startIndex > endIndex) {
        throw IndexOutOfBoundsException("start=$startIndex, end=$endIndex, length=$length")
    }
    val sb = StringBuilder()
    sb.append(buildStringFromCharRange(chars, 0, startIndex))
    sb.append(buildStringFromCharRange(chars, endIndex, length))
    return sb.toString()
}

public fun String.removeRange(range: IntRange): String =
    this.removeRange(range.first, range.last + 1)

public fun String.replaceRange(startIndex: Int, endIndex: Int, replacement: CharSequence): String {
    val chars = this.toString().toList()
    val length = chars.size
    if (startIndex < 0 || startIndex > length || endIndex < 0 || endIndex > length || startIndex > endIndex) {
        throw IndexOutOfBoundsException("start=$startIndex, end=$endIndex, length=$length")
    }
    val sb = StringBuilder()
    sb.append(buildStringFromCharRange(chars, 0, startIndex))
    sb.append(replacement.toString())
    sb.append(buildStringFromCharRange(chars, endIndex, length))
    return sb.toString()
}

public fun String.replaceRange(range: IntRange, replacement: CharSequence): String =
    this.replaceRange(range.first, range.last + 1, replacement)
