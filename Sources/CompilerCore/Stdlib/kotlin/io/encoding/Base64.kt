package kotlin.io.encoding

import kotlin.internal.KsSymbolName

// KSP-482: Base64 encode/decode/padding logic migrated to pure Kotlin.
// Migration source: Sources/Runtime/RuntimeBase64.swift (25 kk_base64_* @_cdecl entries, all deleted).
// Only the OutputStream.encodingWith stream wrapper stays as a runtime bridge
// (renamed kk_output_stream_encodingWith -> __kk_output_stream_encodingWith),
// since it wraps a stateful native OutputStream sink.

private const val STANDARD_ALPHABET = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
private const val URL_SAFE_ALPHABET = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_"
// RFC 2045 (MIME) wraps at 76 chars; RFC 1421 (PEM) wraps at 64. Real Kotlin
// keeps these distinct (`lineLengthMime`/`lineLengthPem`) even though both
// otherwise share the standard alphabet.
private const val MIME_LINE_LENGTH = 76
private const val PEM_LINE_LENGTH = 64

public open class Base64 internal constructor(
    internal val alphabetChars: String,
    // 0 means "do not wrap"; a positive value is the line-wrap width.
    private val lineLength: Int
) {
    internal var padding: PaddingOption = PaddingOption.PRESENT

    public enum class PaddingOption {
        PRESENT,
        ABSENT,
        PRESENT_OPTIONAL,
        ABSENT_OPTIONAL,
    }

    public open fun withPadding(option: PaddingOption): Base64 {
        val copy = Base64(alphabetChars, lineLength)
        copy.padding = option
        return copy
    }

    public open fun encode(source: ByteArray, startIndex: Int = 0, endIndex: Int = source.size): String {
        checkSourceBounds(source.size, startIndex, endIndex)
        val raw = encodeRaw(source, startIndex, endIndex)
        return if (lineLength > 0) wrapAtLineLength(raw) else raw
    }

    public open fun encodeToByteArray(
        source: ByteArray,
        startIndex: Int = 0,
        endIndex: Int = source.size
    ): ByteArray = encode(source, startIndex, endIndex).encodeToByteArray()

    public open fun encodeIntoByteArray(
        source: ByteArray,
        destination: ByteArray,
        destinationOffset: Int = 0,
        startIndex: Int = 0,
        endIndex: Int = source.size
    ): Int {
        val encoded = encodeToByteArray(source, startIndex, endIndex)
        encoded.copyInto(destination, destinationOffset)
        return encoded.size
    }

    @IgnorableReturnValue
    public open fun <A : Appendable> encodeToAppendable(
        source: ByteArray,
        destination: A,
        startIndex: Int = 0,
        endIndex: Int = source.size
    ): A {
        destination.append(encode(source, startIndex, endIndex))
        return destination
    }

    public open fun decode(source: ByteArray, startIndex: Int = 0, endIndex: Int = source.size): ByteArray {
        checkSourceBounds(source.size, startIndex, endIndex)
        return decode(source.decodeToString(startIndex, endIndex))
    }

    public open fun decodeIntoByteArray(
        source: ByteArray,
        destination: ByteArray,
        destinationOffset: Int = 0,
        startIndex: Int = 0,
        endIndex: Int = source.size
    ): Int {
        val decoded = decode(source, startIndex, endIndex)
        decoded.copyInto(destination, destinationOffset)
        return decoded.size
    }

    public open fun decode(source: CharSequence, startIndex: Int = 0, endIndex: Int = source.length): ByteArray {
        checkSourceBounds(source.length, startIndex, endIndex)
        val text = source.toString().substring(startIndex, endIndex)
        val sanitized = if (lineLength > 0) filterToAlphabet(text) else text
        return decodeRaw(sanitized)
    }

    public open fun decodeIntoByteArray(
        source: CharSequence,
        destination: ByteArray,
        destinationOffset: Int = 0,
        startIndex: Int = 0,
        endIndex: Int = source.length
    ): Int {
        val decoded = decode(source, startIndex, endIndex)
        decoded.copyInto(destination, destinationOffset)
        return decoded.size
    }

    private fun encodeRaw(source: ByteArray, startIndex: Int, endIndex: Int): String {
        val sb = StringBuilder()
        val addPadding = padding == PaddingOption.PRESENT || padding == PaddingOption.PRESENT_OPTIONAL
        var i = startIndex
        while (i + 2 < endIndex) {
            val b0 = source[i].toInt() and 0xFF
            val b1 = source[i + 1].toInt() and 0xFF
            val b2 = source[i + 2].toInt() and 0xFF
            sb.append(alphabetChars[b0 shr 2])
            sb.append(alphabetChars[((b0 and 0x03) shl 4) or (b1 shr 4)])
            sb.append(alphabetChars[((b1 and 0x0F) shl 2) or (b2 shr 6)])
            sb.append(alphabetChars[b2 and 0x3F])
            i += 3
        }
        val remaining = endIndex - i
        if (remaining == 1) {
            val b0 = source[i].toInt() and 0xFF
            sb.append(alphabetChars[b0 shr 2])
            sb.append(alphabetChars[(b0 and 0x03) shl 4])
            if (addPadding) sb.append("==")
        } else if (remaining == 2) {
            val b0 = source[i].toInt() and 0xFF
            val b1 = source[i + 1].toInt() and 0xFF
            sb.append(alphabetChars[b0 shr 2])
            sb.append(alphabetChars[((b0 and 0x03) shl 4) or (b1 shr 4)])
            sb.append(alphabetChars[(b1 and 0x0F) shl 2])
            if (addPadding) sb.append("=")
        }
        return sb.toString()
    }

    private fun wrapAtLineLength(raw: String): String {
        if (raw.length <= lineLength) return raw
        val sb = StringBuilder()
        var index = 0
        while (index < raw.length) {
            val end = if (index + lineLength < raw.length) index + lineLength else raw.length
            if (index != 0) sb.append("\r\n")
            sb.append(raw.substring(index, end))
            index = end
        }
        return sb.toString()
    }

    // RFC 2045 MIME decoders ignore every character outside the alphabet
    // (whitespace, CRLF, control characters), rather than rejecting them.
    private fun filterToAlphabet(source: String): String {
        val sb = StringBuilder()
        var i = 0
        while (i < source.length) {
            val c = source[i]
            if (c == '=' || alphabetChars.indexOf(c) >= 0) {
                sb.append(c)
            }
            i += 1
        }
        return sb.toString()
    }

    private fun decodeRaw(source: String): ByteArray {
        val hasPadding = source.indexOf('=') >= 0
        when (padding) {
            PaddingOption.PRESENT ->
                if (!hasPadding && source.length % 4 != 0) {
                    throw IllegalArgumentException("Missing base64 padding")
                }
            PaddingOption.ABSENT ->
                if (hasPadding) {
                    throw IllegalArgumentException("Unexpected base64 padding in ABSENT mode")
                }
            PaddingOption.PRESENT_OPTIONAL, PaddingOption.ABSENT_OPTIONAL -> {
                // Accept either form.
            }
        }

        var end = source.length
        while (end > 0 && source[end - 1] == '=') end -= 1

        val bytes = ArrayList<Byte>()
        var buffer = 0
        var bitsCollected = 0
        var i = 0
        while (i < end) {
            val c = source[i]
            val value = alphabetChars.indexOf(c)
            if (value < 0) {
                throw IllegalArgumentException("Illegal base64 character in input")
            }
            buffer = (buffer shl 6) or value
            bitsCollected += 6
            if (bitsCollected >= 8) {
                bitsCollected -= 8
                bytes.add(((buffer shr bitsCollected) and 0xFF).toByte())
            }
            i += 1
        }
        return bytes.toByteArray()
    }

    private fun checkSourceBounds(sourceSize: Int, startIndex: Int, endIndex: Int) {
        if (startIndex < 0 || endIndex < 0 || startIndex > sourceSize || endIndex > sourceSize) {
            throw IndexOutOfBoundsException("startIndex: $startIndex, endIndex: $endIndex, size: $sourceSize")
        }
        if (startIndex > endIndex) {
            throw IllegalArgumentException("startIndex: $startIndex must be less than or equal to endIndex: $endIndex")
        }
    }

    public companion object Default : Base64(STANDARD_ALPHABET, 0) {
        public val UrlSafe: Base64 = Base64(URL_SAFE_ALPHABET, 0)
        public val Mime: Base64 = Base64(STANDARD_ALPHABET, MIME_LINE_LENGTH)
        public val Pem: Base64 = Base64(STANDARD_ALPHABET, PEM_LINE_LENGTH)
    }
}

@KsSymbolName("__kk_output_stream_encodingWith")
private external fun __outputStreamEncodingWith(
    stream: java.io.OutputStream,
    alphabet: String,
    addPadding: Boolean
): java.io.OutputStream

public fun java.io.OutputStream.encodingWith(base64: Base64): java.io.OutputStream =
    __outputStreamEncodingWith(
        this,
        base64.alphabetChars,
        base64.padding == Base64.PaddingOption.PRESENT || base64.padding == Base64.PaddingOption.PRESENT_OPTIONAL
    )
