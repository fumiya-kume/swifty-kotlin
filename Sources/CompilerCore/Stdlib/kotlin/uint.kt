package kotlin

// KSP-790: Keep the UInt top-level implementation family source-backed.
@PublishedApi
internal fun uintRemainder(v1: UInt, v2: UInt): UInt =
    (v1.toLong() % v2.toLong()).toUInt()

@PublishedApi
internal fun uintDivide(v1: UInt, v2: UInt): UInt =
    (v1.toLong() / v2.toLong()).toUInt()

@PublishedApi
internal fun uintCompare(v1: Int, v2: Int): Int =
    (v1 xor Int.MIN_VALUE).compareTo(v2 xor Int.MIN_VALUE)

@PublishedApi
internal inline fun uintToULong(value: Int): ULong = ULong(uintToLong(value))

@PublishedApi
internal inline fun uintToLong(value: Int): Long = value.toLong() and 0xFFFF_FFFFL

@PublishedApi
internal inline fun uintToFloat(value: Int): Float = uintToDouble(value).toFloat()

@PublishedApi
internal fun uintToDouble(value: Int): Double =
    (value and Int.MAX_VALUE).toDouble() + (value ushr 31 shl 30).toDouble() * 2

// KSP-790: Keep the primitive UIntArray factory source-backed.
// The compiler's vararg representation is a generic array, so copy each
// element into the primitive array rather than returning the vararg directly.
public inline fun uintArrayOf(vararg elements: UInt): UIntArray {
    val result = UIntArray(elements.size)
    var index = 0
    while (index < elements.size) {
        result[index] = elements[index]
        index++
    }
    return result
}
