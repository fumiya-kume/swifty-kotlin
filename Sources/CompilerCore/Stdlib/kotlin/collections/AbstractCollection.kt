/*
 * Copyright 2010-2024 JetBrains s.r.o. and Kotlin Programming Language contributors.
 * Licensed under the Apache License, Version 2.0.
 *
 * Derived from kotlin-stdlib libraries/stdlib/src/kotlin/collections/AbstractCollection.kt.
 */

package kotlin.collections

// KSP-934: the nominal `Collection<out E>` declaration is source-backed here;
// the compiler-side shell in `HeaderHelpers+SyntheticCollectionTypeFallbacks.swift`
// remains the fallback for contexts without the bundled stdlib.
public interface Collection<out E> : Iterable<E> {
    public val size: Int

    public fun isEmpty(): Boolean

    public operator fun contains(element: @UnsafeVariance E): Boolean

    override fun iterator(): Iterator<E>

    public fun containsAll(elements: Collection<@UnsafeVariance E>): Boolean
}

// KSP-633: the nominal `AbstractCollection<out E>` declaration is source-backed
// here; the compiler-side shell in `HeaderHelpers+SyntheticCollectionTypeFallbacks.swift`
// remains the fallback for contexts without the bundled stdlib.

/**
 * Provides a skeletal implementation of the read-only [Collection] interface.
 */
public abstract class AbstractCollection<out E> protected constructor() : Collection<E> {
    abstract override val size: Int

    abstract override fun iterator(): Iterator<E>

    override fun contains(element: @UnsafeVariance E): Boolean {
        val iterator = iterator()
        while (iterator.hasNext()) {
            if (iterator.next() == element) return true
        }
        return false
    }

    override fun containsAll(elements: Collection<@UnsafeVariance E>): Boolean {
        val iterator = elements.iterator()
        while (iterator.hasNext()) {
            if (!contains(iterator.next())) return false
        }
        return true
    }

    override fun isEmpty(): Boolean = size == 0
}

// KSP-957: source-backed implementations for the generic Iterable and Map
// on-family functions. Keep the receiver type in the return value, matching
// Kotlin 2.3.10's generated common stdlib sources.
@SinceKotlin("1.1")
@Suppress("UNCHECKED_CAST")
public inline fun <T, C : Iterable<T>> C.onEach(action: (T) -> Unit): C {
    val source = this as Iterable<T>
    for (element in source) action(element)
    return this
}

@SinceKotlin("1.4")
@Suppress("UNCHECKED_CAST")
public inline fun <T, C : Iterable<T>> C.onEachIndexed(action: (index: Int, T) -> Unit): C {
    val source = this as Iterable<T>
    source.forEachIndexed(action)
    return this
}

@SinceKotlin("1.1")
@Suppress("UNCHECKED_CAST")
public inline fun <K, V, M : Map<out K, V>> M.onEach(action: (Map.Entry<K, V>) -> Unit): M {
    val source = this as Map<K, V>
    for (element in source.entries) action(element)
    return this
}

@SinceKotlin("1.4")
@Suppress("UNCHECKED_CAST")
public inline fun <K, V, M : Map<out K, V>> M.onEachIndexed(action: (index: Int, Map.Entry<K, V>) -> Unit): M {
    val source = this as Map<K, V>
    source.entries.forEachIndexed(action)
    return this
}
