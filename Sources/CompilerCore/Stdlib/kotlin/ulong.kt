package kotlin

// KSP-791: Keep the ULong primitive-array factory source-backed while
// preserving copy semantics for spread arguments.
public inline fun ulongArrayOf(vararg elements: ULong): ULongArray {
    val result = ULongArray(elements.size)
    var index = 0
    while (index < elements.size) {
        result[index] = elements[index]
        index += 1
    }
    return result
}

@PublishedApi
internal fun ulongCompare(v1: Long, v2: Long): Int {
    if (v1 == v2) return 0
    if ((v1 < 0L) != (v2 < 0L)) return if (v1 < 0L) 1 else -1
    return if (v1 < v2) -1 else 1
}

@PublishedApi
internal fun ulongDivide(v1: ULong, v2: ULong): ULong = v1 / v2

@PublishedApi
internal fun ulongRemainder(v1: ULong, v2: ULong): ULong = v1 % v2

@PublishedApi
internal fun ulongToDouble(value: Long): Double {
    if (value < 0L) {
        return 9223372036854775808.0 + (value and Long.MAX_VALUE).toDouble()
    }
    return value.toDouble()
}

@PublishedApi
internal fun ulongToFloat(value: Long): Float {
    if (value < 0L) {
        return 9223372036854775808.0f + (value and Long.MAX_VALUE).toFloat()
    }
    return value.toFloat()
}
