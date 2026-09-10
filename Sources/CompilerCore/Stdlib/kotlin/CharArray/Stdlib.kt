package kotlin

/**
 * Kotlin stdlib `CharArray(size) { init }` constructor.
 *
 * The size-only constructor remains compiler-provided; this overload is
 * implemented as ordinary bundled Kotlin source.
 */
public inline fun CharArray(size: Int, init: (Int) -> Char): CharArray {
    val result = CharArray(size)
    var index = 0
    while (index < size) {
        result[index] = init(index)
        index++
    }
    return result
}
