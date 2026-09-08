package kotlin.text

// KSP-663: Char サロゲート演算とコードポイント変換を bundled Kotlin 化。
// 残留ブリッジ: Char↔Int 変換 (kk_int_to_char) のみを CharConversions の
// __charFromCode 経由で再利用。

/**
 * Returns `true` if this character is a Unicode surrogate code unit.
 */
public fun Char.isSurrogate(): Boolean = this >= '\uD800' && this <= '\uDFFF'

/**
 * Returns `true` if this character is a Unicode high-surrogate code unit
 * (also known as leading-surrogate code unit).
 */
public fun Char.isHighSurrogate(): Boolean = this >= '\uD800' && this <= '\uDBFF'

/**
 * Returns `true` if this character is a Unicode low-surrogate code unit
 * (also known as trailing-surrogate code unit).
 */
public fun Char.isLowSurrogate(): Boolean = this >= '\uDC00' && this <= '\uDFFF'

/**
 * Returns `true` if this CharSequence has Unicode surrogate pair at the specified [index].
 */
public fun CharSequence.hasSurrogatePairAt(index: Int): Boolean {
    return index >= 0
            && index <= length - 2
            && this[index].isHighSurrogate()
            && this[index + 1].isLowSurrogate()
}

/**
 * Checks if the codepoint specified is a supplementary codepoint or not.
 */
@kotlin.experimental.ExperimentalNativeApi
public fun Char.Companion.isSupplementaryCodePoint(codepoint: Int): Boolean =
    codepoint in 0x10000..0x10FFFF

/**
 * Checks if the specified [high] and [low] chars are [Char.isHighSurrogate]
 * and [Char.isLowSurrogate] correspondingly.
 */
@kotlin.experimental.ExperimentalNativeApi
public fun Char.Companion.isSurrogatePair(high: Char, low: Char): Boolean =
    high.isHighSurrogate() && low.isLowSurrogate()

/**
 * Converts a surrogate pair to a unicode code point.
 * Doesn't validate that the characters are a valid surrogate pair.
 */
@kotlin.experimental.ExperimentalNativeApi
public fun Char.Companion.toCodePoint(high: Char, low: Char): Int =
    (((high - '\uD800') shl 10) + (low - '\uDC00')) + 0x10000

/**
 * Converts the codepoint specified to a char array. If the codepoint is not
 * supplementary, the method will return an array with one element;
 * otherwise it will return an array with a high surrogate in [0] and a low
 * surrogate in [1].
 */
@kotlin.experimental.ExperimentalNativeApi
public fun Char.Companion.toChars(codePoint: Int): CharArray {
    return if (codePoint in 0x0000..0xFFFF) {
        val result = CharArray(1)
        result[0] = __charFromCode(codePoint)
        result
    } else if (codePoint in 0x10000..0x10FFFF) {
        val offset = codePoint - 0x10000
        val high = 0xD800 + (offset shr 10)
        val low = 0xDC00 + (offset and 0x3FF)
        val result = CharArray(2)
        result[0] = __charFromCode(high)
        result[1] = __charFromCode(low)
        result
    } else {
        throw IllegalArgumentException()
    }
}
