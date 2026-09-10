/*
 * Copyright 2010-2024 JetBrains s.r.o. and Kotlin Programming Language contributors.
 * Licensed under the Apache License, Version 2.0.
 *
 * Derived from kotlin-stdlib <libraries/stdlib/src/kotlin/collections/Grouping.kt>.
 */

package kotlin.collections

/**
 * Represents a source of elements with a [keyOf] function, which can be applied to each element
 * to get its key.
 */
public interface Grouping<T, out K> {
    /** Returns an [Iterator] over the elements of the source of this grouping. */
    public fun sourceIterator(): Iterator<T>

    /** Extracts the key of an [element]. */
    public fun keyOf(element: T): K
}

/**
 * Creates a [Grouping] source from an iterable to be used later with one of group-and-fold operations
 * using the specified [keySelector] function to extract a key from each element.
 */
public fun <T, K> Iterable<T>.groupingBy(keySelector: (T) -> K): Grouping<T, K> {
    val source = this
    return object : Grouping<T, K> {
        override fun sourceIterator(): Iterator<T> = source.iterator()
        override fun keyOf(element: T): K = keySelector(element)
    }
}

/**
 * Groups elements from the [Grouping] source by key and applies [operation] to the elements of each group
 * sequentially, passing the previously accumulated value and the current element as arguments, and stores
 * the results in the given [destination] map.
 */
public inline fun <T, K, R, M : MutableMap<in K, R>> Grouping<T, K>.aggregateTo(
    destination: M,
    operation: (K, R?, T, Boolean) -> R
): M {
    // KSwiftK does not dispatch containsKey through the bounded M type parameter.
    val map: MutableMap<in K, R> = destination
    val iterator = sourceIterator()
    while (iterator.hasNext()) {
        val element = iterator.next()
        val key = keyOf(element)
        val accumulator = map[key]
        val first = accumulator == null && !map.containsKey(key)
        map[key] = operation(key, accumulator, element, first)
    }
    return destination
}

/**
 * Groups elements from the [Grouping] source by key and applies [operation] to the elements of each group
 * sequentially, passing the previously accumulated value and the current element as arguments.
 */
@Suppress("UNCHECKED_CAST")
public fun <T, K, R> Grouping<T, K>.aggregate(
    operation: (K, R?, T, Boolean) -> R
): Map<K, R> = aggregateTo(mutableMapOf<K, R>(), operation) as Map<K, R>

/**
 * Groups elements from the [Grouping] source by key and applies [operation] to the elements of each group
 * sequentially, starting with the value provided by [initialValueSelector], and stores the results
 * in the given [destination] map.
 */
@Suppress("UNCHECKED_CAST")
public inline fun <T, K, R, M : MutableMap<in K, R>> Grouping<T, K>.foldTo(
    destination: M,
    initialValueSelector: (K, T) -> R,
    operation: (K, R, T) -> R
): M {
    val map: MutableMap<in K, R> = destination
    val iterator = sourceIterator()
    while (iterator.hasNext()) {
        val element = iterator.next()
        val key = keyOf(element)
        val current = map[key]
        val accumulator = if (current == null && !map.containsKey(key)) {
            initialValueSelector(key, element)
        } else {
            current as R
        }
        map[key] = operation(key, accumulator, element)
    }
    return destination
}

/**
 * Groups elements from the [Grouping] source by key and applies [operation] to the elements of each group
 * sequentially, starting with the value provided by [initialValueSelector].
 */
@Suppress("UNCHECKED_CAST")
public fun <T, K, R> Grouping<T, K>.fold(
    initialValueSelector: (K, T) -> R,
    operation: (K, R, T) -> R
): Map<K, R> = foldTo(mutableMapOf<K, R>(), initialValueSelector, operation) as Map<K, R>

/**
 * Groups elements from the [Grouping] source by key and applies [operation] to the elements of each group
 * sequentially, starting with [initialValue], and stores the results in the given [destination] map.
 */
@Suppress("UNCHECKED_CAST")
public inline fun <T, K, R, M : MutableMap<in K, R>> Grouping<T, K>.foldTo(
    destination: M,
    initialValue: R,
    operation: (R, T) -> R
): M {
    val map: MutableMap<in K, R> = destination
    val iterator = sourceIterator()
    while (iterator.hasNext()) {
        val element = iterator.next()
        val key = keyOf(element)
        val current = map[key]
        val accumulator = if (current == null && !map.containsKey(key)) {
            initialValue
        } else {
            current as R
        }
        map[key] = operation(accumulator, element)
    }
    return destination
}

/**
 * Groups elements from the [Grouping] source by key and applies [operation] to the elements of each group
 * sequentially, starting with [initialValue].
 */
@Suppress("UNCHECKED_CAST")
public fun <T, K, R> Grouping<T, K>.fold(
    initialValue: R,
    operation: (R, T) -> R
): Map<K, R> = foldTo(mutableMapOf<K, R>(), initialValue, operation) as Map<K, R>

/**
 * Groups elements from the [Grouping] source by key and applies the reducing [operation] to the elements
 * of each group sequentially, storing the results in the given [destination] map.
 */
@Suppress("UNCHECKED_CAST")
public inline fun <S, T : S, K, M : MutableMap<in K, S>> Grouping<T, K>.reduceTo(
    destination: M,
    operation: (K, S, T) -> S
): M {
    val map: MutableMap<in K, S> = destination
    val iterator = sourceIterator()
    while (iterator.hasNext()) {
        val element = iterator.next()
        val key = keyOf(element)
        val current = map[key]
        val accumulator: S = if (current == null && !map.containsKey(key)) {
            element as S
        } else {
            operation(key, current as S, element)
        }
        map.put(key, accumulator)
    }
    return destination
}

/**
 * Groups elements from the [Grouping] source by key and applies the reducing [operation] to the elements
 * of each group sequentially.
 */
@Suppress("UNCHECKED_CAST")
public fun <T, K> Grouping<T, K>.reduce(
    operation: (K, T, T) -> T
): Map<K, T> = reduceTo(mutableMapOf<K, T>(), operation) as Map<K, T>

/**
 * Groups elements from the [Grouping] source by key and counts elements in each group
 * into the given [destination] map.
 */
public fun <T, K, M : MutableMap<in K, Int>> Grouping<T, K>.eachCountTo(destination: M): M {
    val map: MutableMap<in K, Int> = destination
    val iterator = sourceIterator()
    while (iterator.hasNext()) {
        val element = iterator.next()
        val key = keyOf(element)
        val current = map[key]
        map[key] = if (current == null) 1 else current + 1
    }
    return destination
}

/**
 * Groups elements from the [Grouping] source by key and counts elements in each group.
 */
@Suppress("UNCHECKED_CAST")
public fun <T, K> Grouping<T, K>.eachCount(): Map<K, Int> =
    eachCountTo(mutableMapOf<K, Int>()) as Map<K, Int>
