package kotlin

/**
 * Kotlin stdlib `FloatArray(size) { init }` constructor.
 *
 * The size-only constructor remains compiler-provided; this overload is
 * implemented as ordinary bundled Kotlin source.
 */
public inline fun FloatArray(size: Int, init: (Int) -> Float): FloatArray {
    val result = FloatArray(size)
    var index = 0
    while (index < size) {
        result[index] = init(index)
        index++
    }
    return result
}
