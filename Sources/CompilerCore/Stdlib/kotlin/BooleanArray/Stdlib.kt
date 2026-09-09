package kotlin

/**
 * Kotlin stdlib `BooleanArray(size) { init }` constructor.
 *
 * The size-only constructor remains compiler-provided; this overload is
 * implemented as ordinary bundled Kotlin source.
 */
public inline fun BooleanArray(size: Int, init: (Int) -> Boolean): BooleanArray {
    val result = BooleanArray(size)
    var index = 0
    while (index < size) {
        result[index] = init(index)
        index++
    }
    return result
}
