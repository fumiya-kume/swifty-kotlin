/*
 * Copyright 2010-2024 JetBrains s.r.o. and Kotlin Programming Language contributors.
 * Licensed under the Apache License, Version 2.0.
 *
 * Derived from kotlin-stdlib libraries/stdlib/src/kotlin/collections/MutableCollections.kt
 * (builtins declaration of kotlin.collections.MutableIterable).
 */

package kotlin.collections

// KSP-633: the nominal `MutableIterable<out T>` declaration is source-backed
// here; the compiler-side shell in
// `HeaderHelpers+SyntheticCollectionTypeFallbacks.swift` remains the fallback
// for contexts without the bundled stdlib.

/**
 * Classes that inherit from this interface can be represented as a sequence of
 * elements that can be iterated over and whose iterator supports removal.
 */
public interface MutableIterable<out T> : Iterable<T> {
    public override operator fun iterator(): MutableIterator<T>
}

/**
 * Removes all elements from this [MutableIterable] that match the given [predicate].
 *
 * @return `true` if any element was removed from this collection, or `false` when no elements were removed and collection was not modified.
 */
@IgnorableReturnValue
public fun <T> MutableIterable<T>.removeAll(predicate: (T) -> Boolean): Boolean = filterInPlace(predicate, true)

/**
 * Retains only elements of this [MutableIterable] that match the given [predicate].
 *
 * @return `true` if any element was removed from this collection, or `false` when all elements were retained and collection was not modified.
 */
@IgnorableReturnValue
public fun <T> MutableIterable<T>.retainAll(predicate: (T) -> Boolean): Boolean = filterInPlace(predicate, false)

private fun <T> MutableIterable<T>.filterInPlace(
    predicate: (T) -> Boolean,
    predicateResultToRemove: Boolean
): Boolean {
    var result = false
    val iterator: MutableIterator<T> = iterator()
    while (iterator.hasNext()) {
        if (predicate(iterator.next()) == predicateResultToRemove) {
            iterator.remove()
            result = true
        }
    }
    return result
}
