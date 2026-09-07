package kotlin.text

import kotlin.internal.KsSymbolName

/**
 * A mutable sequence of characters backed by the KSwiftK runtime string-builder
 * handle. Public operations are implemented in Kotlin; only the small mutable
 * buffer bridge below crosses into the runtime.
 */
public class StringBuilder : Appendable, CharSequence {
    constructor()
    constructor(content: String)
    constructor(capacity: Int)

    override val length: Int
        get() = __kk_string_builder_length()

    override operator fun get(index: Int): Char {
        checkElementIndex(index)
        return toString()[index]
    }

    fun subSequence(startIndex: Int, endIndex: Int): CharSequence =
        toString().substring(startIndex, endIndex)

    override fun append(value: Char): StringBuilder =
        __kk_string_builder_append_obj(value.toString())

    override fun append(value: CharSequence?): StringBuilder =
        __kk_string_builder_append_obj(if (value == null) "null" else value as String)

    override fun append(value: CharSequence?, startIndex: Int, endIndex: Int): StringBuilder =
        appendRange(if (value == null) "null" else value as String, startIndex, endIndex)

    fun append(value: String?): StringBuilder =
        __kk_string_builder_append_obj(value)

    fun append(value: Boolean): StringBuilder =
        __kk_string_builder_append_obj(value.toString())

    fun append(value: Int): StringBuilder =
        __kk_string_builder_append_obj(value.toString())

    fun append(value: Long): StringBuilder =
        __kk_string_builder_append_obj(value.toString())

    fun append(value: Float): StringBuilder =
        __kk_string_builder_append_obj(value.toString())

    fun append(value: Double): StringBuilder =
        __kk_string_builder_append_obj(value.toString())

    fun append(value: Any?): StringBuilder =
        __kk_string_builder_append_obj(value)

    fun append(value: Byte): StringBuilder =
        __kk_string_builder_append_obj(value.toString())

    fun append(value: Short): StringBuilder =
        __kk_string_builder_append_obj(value.toString())

    fun append(value: CharArray): StringBuilder =
        appendRange(value, 0, value.size)

    fun append(vararg value: Any?): StringBuilder {
        var index = 0
        while (index < value.size) {
            __kk_string_builder_append_obj(value[index].toString())
            index += 1
        }
        return this
    }

    fun appendLine(value: Any?): StringBuilder {
        __kk_string_builder_append_obj(value.toString())
        __kk_string_builder_append_obj("\n")
        return this
    }

    fun appendLine(): StringBuilder {
        __kk_string_builder_append_obj("\n")
        return this
    }

    fun insert(index: Int, value: Any?): StringBuilder =
        insertString(index, value.toString())

    fun insert(index: Int, value: String?): StringBuilder =
        insertString(index, if (value == null) "null" else value)

    fun insert(index: Int, value: Char): StringBuilder =
        insertString(index, value.toString())

    fun insert(index: Int, value: Boolean): StringBuilder =
        insertString(index, value.toString())

    fun insert(index: Int, value: Int): StringBuilder =
        insertString(index, value.toString())

    fun insert(index: Int, value: Long): StringBuilder =
        insertString(index, value.toString())

    fun insert(index: Int, value: Float): StringBuilder =
        insertString(index, value.toString())

    fun insert(index: Int, value: Double): StringBuilder =
        insertString(index, value.toString())

    fun insert(index: Int, value: Byte): StringBuilder =
        insertString(index, value.toString())

    fun insert(index: Int, value: Short): StringBuilder =
        insertString(index, value.toString())

    fun insert(index: Int, value: CharArray): StringBuilder =
        insertRange(index, value, 0, value.size)

    fun insert(index: Int, value: CharSequence?): StringBuilder =
        __kk_string_builder_insert_char_sequence(index, value)

    fun delete(startIndex: Int, endIndex: Int): StringBuilder {
        checkRange(startIndex, endIndex)
        val current = toString()
        return resetTo(current.substring(0, startIndex) + current.substring(endIndex))
    }

    fun deleteRange(startIndex: Int, endIndex: Int): StringBuilder =
        delete(startIndex, endIndex)

    fun clear(): StringBuilder =
        __kk_string_builder_clear()

    fun reverse(): StringBuilder {
        val current = toString()
        var result = ""
        var index = current.length - 1
        while (index >= 0) {
            result = result + current[index]
            index -= 1
        }
        return resetTo(result)
    }

    fun deleteCharAt(index: Int): StringBuilder {
        checkElementIndex(index)
        val current = toString()
        return resetTo(current.substring(0, index) + current.substring(index + 1))
    }

    fun deleteAt(index: Int): StringBuilder =
        deleteCharAt(index)

    operator fun set(index: Int, value: Char): Unit {
        setCharAt(index, value)
    }

    fun appendRange(value: CharSequence, startIndex: Int, endIndex: Int): StringBuilder {
        append((value as String).substring(startIndex, endIndex))
        return this
    }

    fun appendRange(value: CharArray, startIndex: Int, endIndex: Int): StringBuilder =
        __kk_string_builder_append_char_array(value, startIndex, endIndex)

    fun insertRange(index: Int, value: CharSequence, startIndex: Int, endIndex: Int): StringBuilder =
        insertString(index, (value as String).substring(startIndex, endIndex))

    fun insertRange(index: Int, value: CharArray, startIndex: Int, endIndex: Int): StringBuilder =
        __kk_string_builder_insert_char_array(index, value, startIndex, endIndex)

    fun indexOf(string: String): Int =
        __kk_string_builder_index_of(string, 0)

    fun indexOf(string: String, startIndex: Int): Int =
        __kk_string_builder_index_of(string, startIndex)

    fun lastIndexOf(string: String): Int =
        __kk_string_builder_last_index_of(string, __kk_string_builder_length_utf16())

    fun lastIndexOf(string: String, startIndex: Int): Int =
        __kk_string_builder_last_index_of(string, startIndex)

    fun setLength(newLength: Int): Unit {
        __kk_string_builder_set_length(newLength)
    }

    fun substring(startIndex: Int): String =
        __kk_string_builder_substring(startIndex, __kk_string_builder_length_utf16())

    fun substring(startIndex: Int, endIndex: Int): String =
        __kk_string_builder_substring(startIndex, endIndex)

    fun toCharArray(
        destination: CharArray,
        destinationOffset: Int = 0,
        startIndex: Int = 0,
        endIndex: Int = __kk_string_builder_length_utf16()
    ): Unit {
        __kk_string_builder_to_char_array(destination, destinationOffset, startIndex, endIndex)
    }

    fun setRange(startIndex: Int, endIndex: Int, value: String): StringBuilder =
        replaceString(startIndex, endIndex, value, false)

    fun replace(start: Int, end: Int, str: String): StringBuilder =
        replaceString(start, end, str, true)

    fun setCharAt(index: Int, value: Char): Unit {
        checkElementIndex(index)
        replaceString(index, index + 1, value.toString(), false)
    }

    fun capacity(): Int =
        currentLength() + 16

    fun ensureCapacity(minimumCapacity: Int): Unit {
    }

    fun trimToSize(): Unit {
    }

    override fun toString(): String =
        __kk_string_builder_toString()

    private fun insertString(index: Int, value: String): StringBuilder {
        return __kk_string_builder_insert_obj(index, value)
    }

    private fun replaceString(startIndex: Int, endIndex: Int, value: String, clampEnd: Boolean): StringBuilder {
        val current = toString()
        val effectiveEnd = if (clampEnd && endIndex > current.length) current.length else endIndex
        if (startIndex < 0 || startIndex > current.length || effectiveEnd < startIndex || effectiveEnd > current.length) {
            throw IndexOutOfBoundsException(
                "startIndex: $startIndex, endIndex: $endIndex, length: ${current.length}"
            )
        }
        return resetTo(current.substring(0, startIndex) + value + current.substring(effectiveEnd))
    }

    private fun resetTo(value: String): StringBuilder {
        __kk_string_builder_clear()
        __kk_string_builder_append_obj(value)
        return this
    }

    private fun checkInsertIndex(index: Int) {
        val currentLength = currentLength()
        if (index < 0 || index > currentLength) {
            throw IndexOutOfBoundsException("index=$index, length=$currentLength")
        }
    }

    private fun checkElementIndex(index: Int) {
        val currentLength = currentLength()
        if (index < 0 || index >= currentLength) {
            throw IndexOutOfBoundsException("index=$index, length=$currentLength")
        }
    }

    private fun checkRange(startIndex: Int, endIndex: Int) {
        val currentLength = currentLength()
        if (startIndex < 0 || startIndex > currentLength || endIndex < startIndex || endIndex > currentLength) {
            throw IndexOutOfBoundsException("startIndex=$startIndex, endIndex=$endIndex, length=$currentLength")
        }
    }

    private fun currentLength(): Int =
        __kk_string_builder_length()

    @KsSymbolName("__kk_string_builder_append_obj")
    private external fun __kk_string_builder_append_obj(value: Any?): StringBuilder

    @KsSymbolName("__kk_string_builder_append_char_array")
    private external fun __kk_string_builder_append_char_array(value: CharArray, startIndex: Int, endIndex: Int): StringBuilder

    @KsSymbolName("__kk_string_builder_insert_obj")
    private external fun __kk_string_builder_insert_obj(index: Int, value: Any?): StringBuilder

    @KsSymbolName("__kk_string_builder_insert_char_sequence")
    private external fun __kk_string_builder_insert_char_sequence(index: Int, value: CharSequence?): StringBuilder

    @KsSymbolName("__kk_string_builder_insert_char_array")
    private external fun __kk_string_builder_insert_char_array(index: Int, value: CharArray, startIndex: Int, endIndex: Int): StringBuilder

    @KsSymbolName("__kk_string_builder_index_of")
    private external fun __kk_string_builder_index_of(value: String, startIndex: Int): Int

    @KsSymbolName("__kk_string_builder_last_index_of")
    private external fun __kk_string_builder_last_index_of(value: String, startIndex: Int): Int

    @KsSymbolName("__kk_string_builder_set_length")
    private external fun __kk_string_builder_set_length(newLength: Int): Unit

    @KsSymbolName("__kk_string_builder_substring")
    private external fun __kk_string_builder_substring(startIndex: Int, endIndex: Int): String

    @KsSymbolName("__kk_string_builder_to_char_array")
    private external fun __kk_string_builder_to_char_array(destination: CharArray, destinationOffset: Int, startIndex: Int, endIndex: Int): Unit

    @KsSymbolName("__kk_string_builder_length_utf16")
    private external fun __kk_string_builder_length_utf16(): Int

    @KsSymbolName("__kk_string_builder_toString")
    private external fun __kk_string_builder_toString(): String

    @KsSymbolName("__kk_string_builder_length_prop")
    private external fun __kk_string_builder_length(): Int

    @KsSymbolName("__kk_string_builder_clear")
    private external fun __kk_string_builder_clear(): StringBuilder
}

public fun buildString(builderAction: StringBuilder.() -> Unit): String {
    val builder = StringBuilder()
    builder.builderAction()
    return builder.toString()
}

public fun buildString(capacity: Int, builderAction: StringBuilder.() -> Unit): String {
    val builder = StringBuilder(capacity)
    builder.builderAction()
    return builder.toString()
}

public fun buildStringBuilder(builderAction: StringBuilder.() -> Unit): StringBuilder {
    val builder = StringBuilder()
    builder.builderAction()
    return builder
}

public fun buildStringBuilder(capacity: Int, builderAction: StringBuilder.() -> Unit): StringBuilder {
    val builder = StringBuilder(capacity)
    builder.builderAction()
    return builder
}
