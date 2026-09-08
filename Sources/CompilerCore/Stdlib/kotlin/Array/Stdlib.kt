package kotlin

/**
 * Kotlin stdlib `Array(size) { init }` constructor.
 *
 * The size-only allocation is compiler-provided, matching Kotlin/Native's
 * published internal constructor. Keeping allocation in the compiler lets
 * the runtime preserve the checked NegativeArraySizeException behavior.
 */
public inline fun <T> Array(size: Int, init: (Int) -> T): Array<T> {
    val result = Array<T>(size)
    var index = 0
    while (index < size) {
        result[index] = init(index)
        index++
    }
    return result
}
