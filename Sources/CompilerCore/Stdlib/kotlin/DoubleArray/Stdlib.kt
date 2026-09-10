package kotlin

/**
 * Kotlin stdlib `DoubleArray(size) { init }` constructor.
 *
 * The size-only constructor remains compiler-provided; this overload is
 * implemented as ordinary bundled Kotlin source.
 */
public inline fun DoubleArray(size: Int, init: (Int) -> Double): DoubleArray {
    val result = DoubleArray(size)
    var index = 0
    while (index < size) {
        result[index] = init(index)
        index++
    }
    return result
}
