package kotlin.text

import kswiftk.internal.*
import kotlin.internal.KsSymbolName

// String search and replace functions migrated from Swift Runtime
// MIGRATION-TEXT-002

/**
 * Returns a new string obtained by replacing all occurrences of the [oldValue] substring
 * in this string with the specified [newValue] string.
 *
 * @param oldValue The substring to be replaced.
 * @param newValue The replacement string.
 * @param ignoreCase `true` to ignore character case when matching [oldValue]. Default is `false`.
 */
public fun String.replace(oldValue: String, newValue: String, ignoreCase: Boolean = false): String {
    // Use the runtime string-to-list bridge for character traversal. The flat
    // String aggregate stores UTF-8 byte length, while Kotlin indexing is
    // character-based; using `length`/`this[i]` here can walk past non-ASCII
    // input and raise StringIndexOutOfBoundsException.
    val sourceChars = toList()
    val oldLength = oldValue.toList().size
    val sourceLength = sourceChars.size
    if (oldLength == 0) {
        val sb = StringBuilder()
        sb.append(newValue)
        var i = 0
        while (i < sourceLength) {
            sb.append(sourceChars[i])
            sb.append(newValue)
            i++
        }
        return sb.toString()
    }
    val sb = StringBuilder()
    var start = 0
    while (true) {
        val idx = indexOf(oldValue, start, ignoreCase)
        if (idx == -1) {
            __kk_appendStringRange(sb, sourceChars, start, sourceLength)
            break
        }
        __kk_appendStringRange(sb, sourceChars, start, idx)
        sb.append(newValue)
        start = idx + oldLength
    }
    return sb.toString()
}

/**
 * Returns a new string obtained by replacing all occurrences of the [oldChar] character
 * in this string with the [newChar] character.
 *
 * @param oldChar The character to replace.
 * @param newChar The replacement character.
 * @param ignoreCase `true` to ignore character case. Default is `false`.
 */
public fun String.replace(oldChar: Char, newChar: Char, ignoreCase: Boolean = false): String {
    val sb = StringBuilder()
    var i = 0
    while (i < length) {
        val c = this[i]
        if (c == oldChar || (ignoreCase && c.lowercaseChar() == oldChar.lowercaseChar())) {
            sb.append(newChar)
        } else {
            sb.append(c)
        }
        i++
    }
    return sb.toString()
}

/**
 * Returns a new string obtained by replacing each occurrence of [regex]
 * with the specified [replacement] string.
 */
public fun String.replace(regex: Regex, replacement: String): String =
    regex.replace(this, replacement)

/**
 * Returns a new string with the first occurrence of [oldValue] replaced with [newValue].
 *
 * @param oldValue The substring to replace the first occurrence of.
 * @param newValue The replacement string.
 * @param ignoreCase `true` to ignore character case when finding [oldValue]. Default is `false`.
 */
public fun String.replaceFirst(oldValue: String, newValue: String, ignoreCase: Boolean = false): String {
    val sourceChars = toList()
    val oldLength = oldValue.toList().size
    val sourceLength = sourceChars.size
    val idx = indexOf(oldValue, 0, ignoreCase)
    if (idx == -1) return this
    val sb = StringBuilder()
    __kk_appendStringRange(sb, sourceChars, 0, idx)
    sb.append(newValue)
    __kk_appendStringRange(sb, sourceChars, idx + oldLength, sourceLength)
    return sb.toString()
}

/**
 * Returns a new string with the first occurrence of [oldChar] replaced with [newChar].
 *
 * @param oldChar The character to replace.
 * @param newChar The replacement character.
 * @param ignoreCase `true` to ignore character case. Default is `false`.
 */
public fun String.replaceFirst(oldChar: Char, newChar: Char, ignoreCase: Boolean = false): String {
    val sb = StringBuilder()
    var replaced = false
    var i = 0
    while (i < length) {
        val c = this[i]
        if (!replaced && (c == oldChar || (ignoreCase && c.lowercaseChar() == oldChar.lowercaseChar()))) {
            sb.append(newChar)
            replaced = true
        } else {
            sb.append(c)
        }
        i++
    }
    if (!replaced) return this
    return sb.toString()
}

/**
 * Returns a new string with the first occurrence of [regex] replaced by [replacement].
 */
public fun String.replaceFirst(regex: Regex, replacement: String): String =
    regex.replaceFirst(this, replacement)

/**
 * Splits this string around matches of [regex].
 */
public fun String.split(regex: Regex): List<String> =
    regex.split(this, 0)

/**
 * Splits this string around matches of [regex], limiting the result to [limit] items.
 */
public fun String.split(regex: Regex, limit: Int): List<String> =
    regex.split(this, limit)

/**
 * Returns `true` if this string matches the [regex].
 */
public fun String.matches(regex: Regex): Boolean =
    __kk_string_matches_regex(regex)

/**
 * Returns `true` if this char sequence matches the given regular expression.
 */
@kotlin.internal.InlineOnly
public inline infix fun CharSequence.matches(regex: Regex): Boolean {
    // Regex currently accepts String input. Preserve indexed CharSequence
    // semantics instead of trusting a custom implementation's toString().
    if (this is String) return regex.matches(this)
    if (this is StringBuilder) return regex.matches(this.toString())
    val builder = StringBuilder()
    var i = 0
    val size = length
    while (i < size) {
        builder.append(this[i])
        i++
    }
    return regex.matches(builder.toString())
}

/**
 * Returns `true` if this string contains a match of [regex].
 */
public operator fun String.contains(regex: Regex): Boolean =
    __kk_string_contains_regex(regex)

/**
 * Returns a [Regex] that matches this string as a pattern.
 */
public fun String.toRegex(): Regex =
    __kk_string_toRegex()

/**
 * Returns a [Regex] that matches this string as a pattern with the given [option].
 */
public fun String.toRegex(option: RegexOption): Regex =
    __kk_string_toRegex_with_option(option)

/**
 * Returns a [Regex] that matches this string as a pattern with the given [options].
 */
public fun String.toRegex(options: Set<RegexOption>): Regex =
    __kk_string_toRegex_with_options(options)

/**
 * Returns the substring before the first occurrence of [delimiter], or
 * [missingDelimiterValue] if this string does not contain [delimiter].
 */
public fun String.substringBefore(delimiter: String, missingDelimiterValue: String = this): String {
    val index = indexOf(delimiter)
    return if (index == -1) missingDelimiterValue else substring(0, index)
}

/** @see substringBefore */
public fun String.substringBefore(delimiter: Char, missingDelimiterValue: String = this): String {
    val index = indexOf(delimiter)
    return if (index == -1) missingDelimiterValue else substring(0, index)
}

/**
 * Returns the substring after the first occurrence of [delimiter], or
 * [missingDelimiterValue] if this string does not contain [delimiter].
 */
public fun String.substringAfter(delimiter: String, missingDelimiterValue: String = this): String {
    val index = indexOf(delimiter)
    return if (index == -1) missingDelimiterValue else substring(index + delimiter.length)
}

/** @see substringAfter */
public fun String.substringAfter(delimiter: Char, missingDelimiterValue: String = this): String {
    val index = indexOf(delimiter)
    return if (index == -1) missingDelimiterValue else substring(index + 1)
}

/**
 * Returns the substring before the last occurrence of [delimiter], or
 * [missingDelimiterValue] if this string does not contain [delimiter].
 */
public fun String.substringBeforeLast(delimiter: String, missingDelimiterValue: String = this): String {
    val index = lastIndexOf(delimiter)
    return if (index == -1) missingDelimiterValue else substring(0, index)
}

/** @see substringBeforeLast */
public fun String.substringBeforeLast(delimiter: Char, missingDelimiterValue: String = this): String {
    val index = lastIndexOf(delimiter)
    return if (index == -1) missingDelimiterValue else substring(0, index)
}

/**
 * Returns the substring after the last occurrence of [delimiter], or
 * [missingDelimiterValue] if this string does not contain [delimiter].
 */
public fun String.substringAfterLast(delimiter: String, missingDelimiterValue: String = this): String {
    val index = lastIndexOf(delimiter)
    return if (index == -1) missingDelimiterValue else substring(index + delimiter.length)
}

/** @see substringAfterLast */
public fun String.substringAfterLast(delimiter: Char, missingDelimiterValue: String = this): String {
    val index = lastIndexOf(delimiter)
    return if (index == -1) missingDelimiterValue else substring(index + 1)
}

/**
 * Replaces everything before the first occurrence of [delimiter] with
 * [replacement], or returns [missingDelimiterValue] if this string does not
 * contain [delimiter].
 */
public fun String.replaceBefore(delimiter: String, replacement: String, missingDelimiterValue: String = this): String {
    val index = indexOf(delimiter)
    return if (index == -1) missingDelimiterValue else replacement + substring(index)
}

/** @see replaceBefore */
public fun String.replaceBefore(delimiter: Char, replacement: String, missingDelimiterValue: String = this): String {
    val index = indexOf(delimiter)
    return if (index == -1) missingDelimiterValue else replacement + substring(index)
}

/**
 * Replaces everything after the first occurrence of [delimiter] (including
 * the delimiter itself) with [replacement], or returns [missingDelimiterValue]
 * if this string does not contain [delimiter].
 */
public fun String.replaceAfter(delimiter: String, replacement: String, missingDelimiterValue: String = this): String {
    val index = indexOf(delimiter)
    return if (index == -1) missingDelimiterValue else substring(0, index + delimiter.length) + replacement
}

/** @see replaceAfter */
public fun String.replaceAfter(delimiter: Char, replacement: String, missingDelimiterValue: String = this): String {
    val index = indexOf(delimiter)
    return if (index == -1) missingDelimiterValue else substring(0, index + 1) + replacement
}

/**
 * Replaces everything after the last occurrence of [delimiter] (including
 * the delimiter itself) with [replacement], or returns [missingDelimiterValue]
 * if this string does not contain [delimiter].
 */
public fun String.replaceAfterLast(delimiter: String, replacement: String, missingDelimiterValue: String = this): String {
    val index = lastIndexOf(delimiter)
    return if (index == -1) missingDelimiterValue else substring(0, index + delimiter.length) + replacement
}

/** @see replaceAfterLast */
public fun String.replaceAfterLast(delimiter: Char, replacement: String, missingDelimiterValue: String = this): String {
    val index = lastIndexOf(delimiter)
    return if (index == -1) missingDelimiterValue else substring(0, index + 1) + replacement
}

/**
 * Replaces everything before the last occurrence of [delimiter] with
 * [replacement], or returns [missingDelimiterValue] if this string does not
 * contain [delimiter].
 */
public fun String.replaceBeforeLast(delimiter: String, replacement: String, missingDelimiterValue: String = this): String {
    val index = lastIndexOf(delimiter)
    return if (index == -1) missingDelimiterValue else replacement + substring(index)
}

/** @see replaceBeforeLast */
public fun String.replaceBeforeLast(delimiter: Char, replacement: String, missingDelimiterValue: String = this): String {
    val index = lastIndexOf(delimiter)
    return if (index == -1) missingDelimiterValue else replacement + substring(index)
}

@KsSymbolName("__kk_string_matches_regex_flat")
private external fun String.__kk_string_matches_regex(regex: Regex): Boolean

@KsSymbolName("__kk_string_contains_regex_flat")
private external fun String.__kk_string_contains_regex(regex: Regex): Boolean

@KsSymbolName("__kk_string_toRegex_flat")
private external fun String.__kk_string_toRegex(): Regex

@KsSymbolName("__kk_string_toRegex_with_option_flat")
private external fun String.__kk_string_toRegex_with_option(option: RegexOption): Regex

@KsSymbolName("__kk_string_toRegex_with_options_flat")
private external fun String.__kk_string_toRegex_with_options(options: Set<RegexOption>): Regex

private fun __kk_appendStringRange(sb: StringBuilder, value: List<Char>, startIndex: Int, endIndex: Int) {
    var i = startIndex
    while (i < endIndex) {
        sb.append(value[i])
        i++
    }
}
