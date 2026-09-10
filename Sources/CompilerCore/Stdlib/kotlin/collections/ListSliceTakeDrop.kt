package kotlin.collections

// MIGRATION-COL-008
// List slice/take/drop helpers migrated to Kotlin source.
// Migration source:
//   Sources/Runtime/RuntimeCollectionHOFMaxMin.swift (kk_list_take, kk_list_takeLast,
//   kk_list_drop, kk_list_dropLast)
//   Sources/Runtime/RuntimeCollectionHOF.swift (kk_list_takeWhile, kk_list_dropWhile,
//   kk_list_takeLastWhile, kk_list_dropLastWhile)
//   Sources/Runtime/RuntimeCollections.swift (kk_list_slice, kk_list_slice_iterable,
//   kk_list_subList)
//
// NOTE: List.subList is declared as returning a view in the real Kotlin stdlib.
// This bundled implementation returns a snapshot copy instead, matching the
// historical runtime behavior and the current RuntimeListBox storage model.

public fun <T> List<T>.take(n: Int): List<T> {
    require(n >= 0) { "Requested element count $n is less than zero." }
    if (n == 0) return emptyList()
    if (n >= size) return toList()
    val result = mutableListOf<T>()
    var i = 0
    while (i < n) {
        result.add(this[i])
        i++
    }
    return result
}

public fun <T> List<T>.takeLast(n: Int): List<T> {
    require(n >= 0) { "Requested element count $n is less than zero." }
    if (n == 0) return emptyList()
    if (n >= size) return toList()
    val result = mutableListOf<T>()
    var i = size - n
    while (i < size) {
        result.add(this[i])
        i++
    }
    return result
}

public fun <T> List<T>.takeWhile(predicate: (T) -> Boolean): List<T> {
    val result = mutableListOf<T>()
    var i = 0
    val sz = size
    while (i < sz) {
        val element = this[i]
        if (predicate(element)) result.add(element) else return result
        i++
    }
    return result
}

public fun <T> List<T>.takeLastWhile(predicate: (T) -> Boolean): List<T> {
    var i = size - 1
    while (i >= 0) {
        if (!predicate(this[i])) {
            return subList(i + 1, size)
        }
        i--
    }
    return toList()
}

public fun <T> List<T>.drop(n: Int): List<T> {
    require(n >= 0) { "Requested element count $n is less than zero." }
    if (n >= size) return emptyList()
    if (n == 0) return toList()
    return subList(n, size)
}

public fun <T> List<T>.dropLast(n: Int): List<T> {
    require(n >= 0) { "Requested element count $n is less than zero." }
    if (n >= size) return emptyList()
    if (n == 0) return toList()
    return subList(0, size - n)
}

public fun <T> List<T>.dropWhile(predicate: (T) -> Boolean): List<T> {
    var i = 0
    while (i < size) {
        if (!predicate(this[i])) {
            return subList(i, size)
        }
        i++
    }
    return emptyList()
}

public fun <T> List<T>.dropLastWhile(predicate: (T) -> Boolean): List<T> {
    var i = size - 1
    while (i >= 0) {
        if (!predicate(this[i])) {
            return subList(0, i + 1)
        }
        i--
    }
    return emptyList()
}

// KSP-1001: Keep the stdlib IntRange overload alongside the Iterable overload.
// The List<Int> argument below remains an unambiguous match for Iterable<Int>.
public fun <T> List<T>.slice(indices: IntRange): List<T> {
    if (indices.isEmpty()) return emptyList()
    val result = mutableListOf<T>()
    for (index in indices) {
        result.add(this[index])
    }
    return result
}

public fun <T> List<T>.slice(indices: Iterable<Int>): List<T> {
    val result = mutableListOf<T>()
    for (index in indices) {
        result.add(this[index])
    }
    return result
}

public fun <T> List<T>.subList(fromIndex: Int, toIndex: Int): List<T> {
    val message = "fromIndex: $fromIndex, toIndex: $toIndex, size: $size"
    if (fromIndex < 0 || toIndex > size || fromIndex > toIndex) {
        throw IndexOutOfBoundsException(message)
    }
    val result = mutableListOf<T>()
    var i = fromIndex
    while (i < toIndex) {
        result.add(this[i])
        i++
    }
    return result
}
