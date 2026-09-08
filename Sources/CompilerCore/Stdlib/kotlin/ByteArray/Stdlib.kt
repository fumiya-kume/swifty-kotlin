package kotlin

/**
 * Kotlin stdlib `ByteArray(size) { init }` constructor.
 *
 * The size-only constructor remains compiler-provided; this overload is
 * implemented as ordinary bundled Kotlin source.
 */
public inline fun ByteArray(size: Int, init: (Int) -> Byte): ByteArray {
    val result = ByteArray(size)
    var index = 0
    while (index < size) {
        result[index] = init(index)
        index++
    }
    return result
}
