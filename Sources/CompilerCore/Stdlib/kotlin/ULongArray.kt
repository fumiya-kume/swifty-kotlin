package kotlin

// KSP-763: Keep the initializer overload source-backed while the size-only
// primitive-array constructor remains a compiler-provided allocation primitive.
public inline fun ULongArray(size: Int, init: (Int) -> ULong): ULongArray {
    val result = ULongArray(size)
    var index = 0
    while (index < size) {
        result[index] = init(index)
        index += 1
    }
    return result
}

/**
 * Internal storage constructor used by the unsigned/signed array view APIs.
 *
 * Kotlin exposes this constructor only to the stdlib implementation. The
 * signed and unsigned arrays intentionally share the same backing storage.
 */
@PublishedApi
internal fun ULongArray(storage: LongArray): ULongArray = storage.asULongArray()
