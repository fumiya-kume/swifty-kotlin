package kotlin.collections

// KSP-939: List(size, init) initializer factory. The List<out E> nominal
// declaration itself already lives in List.kt (KSP-697); indexed access and
// collection members remain compiler/runtime residuals until their dedicated
// migration tasks land.

/**
 * Creates a read-only list whose elements are produced in ascending index order.
 */
@SinceKotlin("1.1")
@kotlin.internal.InlineOnly
public inline fun <T> List(size: Int, init: (index: Int) -> T): List<T> =
    MutableList(size, init)

// MIGRATION-COL-007
// List access helpers migrated to Kotlin source.
// Migration source: Sources/Runtime/RuntimeCollections.swift (kk_list_getOrNull,
// kk_list_elementAt*, kk_list_elementAt) and RuntimeCollectionHOF.swift
// (kk_list_getOrElse, kk_list_elementAtOrElse).

public fun <T> List<T>.getOrNull(index: Int): T? {
    if (index >= 0 && index < size) {
        return this[index]
    }
    return null
}

public fun <T> List<T>.getOrElse(index: Int, defaultValue: (Int) -> T): T {
    if (index >= 0 && index < size) {
        return this[index]
    }
    return defaultValue(index)
}

public fun <T> List<T>.elementAt(index: Int): T {
    if (index < 0 || index >= size) {
        throw IndexOutOfBoundsException("Index $index out of bounds for length $size")
    }
    return this[index]
}

public fun <T> List<T>.elementAtOrNull(index: Int): T? {
    if (index >= 0 && index < size) {
        return this[index]
    }
    return null
}

public fun <T> List<T>.elementAtOrElse(index: Int, defaultValue: (Int) -> T): T {
    if (index >= 0 && index < size) {
        return this[index]
    }
    return defaultValue(index)
}
