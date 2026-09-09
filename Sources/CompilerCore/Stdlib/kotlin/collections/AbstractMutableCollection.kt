/*
 * Copyright 2010-2024 JetBrains s.r.o. and Kotlin Programming Language contributors.
 * Licensed under the Apache License, Version 2.0.
 *
 * Derived from kotlin-stdlib libraries/stdlib/jvm/src/kotlin/collections/AbstractMutableCollection.kt.
 */

package kotlin.collections

// KSP-633: the nominal `AbstractMutableCollection<E>` declaration is
// source-backed here; the compiler-side shell in
// `HeaderHelpers+SyntheticCollectionTypeFallbacks.swift` remains the fallback
// for contexts without the bundled stdlib.

/**
 * Provides a skeletal implementation of the [MutableCollection] interface.
 */
public abstract class AbstractMutableCollection<E> protected constructor() : AbstractCollection<E>(), MutableCollection<E> {
    abstract override fun add(element: E): Boolean

    /**
     * Adds all of the elements of the specified collection to this collection.
     */
    @IgnorableReturnValue
    override fun addAll(elements: Collection<E>): Boolean {
        var changed = false
        for (element in elements) {
            if (add(element)) changed = true
        }
        return changed
    }

    /**
     * Removes a single instance of the specified element from this collection, if it is present.
     */
    @IgnorableReturnValue
    @Suppress("UNCHECKED_CAST")
    override fun remove(element: E): Boolean {
        val iterator = iterator() as MutableIterator<E>
        while (iterator.hasNext()) {
            if (iterator.next() == element) {
                iterator.remove()
                return true
            }
        }
        return false
    }

    /**
     * Removes all of this collection's elements that are also contained in the specified collection.
     */
    @IgnorableReturnValue
    @Suppress("UNCHECKED_CAST")
    override fun removeAll(elements: Collection<E>): Boolean {
        val iterator = iterator() as MutableIterator<E>
        var changed = false
        while (iterator.hasNext()) {
            if (elements.contains(iterator.next())) {
                iterator.remove()
                changed = true
            }
        }
        return changed
    }

    /**
     * Retains only the elements in this collection that are contained in the specified collection.
     */
    @IgnorableReturnValue
    @Suppress("UNCHECKED_CAST")
    override fun retainAll(elements: Collection<E>): Boolean {
        val iterator = iterator() as MutableIterator<E>
        var changed = false
        while (iterator.hasNext()) {
            if (!elements.contains(iterator.next())) {
                iterator.remove()
                changed = true
            }
        }
        return changed
    }

    /**
     * Removes all elements from this collection.
     */
    @Suppress("UNCHECKED_CAST")
    override fun clear(): Unit {
        val iterator = iterator() as MutableIterator<E>
        while (iterator.hasNext()) {
            val _ = iterator.next()
            iterator.remove()
        }
    }
}

// KSP-1019: these are top-level MutableCollection extensions. They are kept
// separate from the nominal AbstractMutableCollection class above, matching
// the kotlin-stdlib source ownership and preserving member dispatch.

/**
 * Removes a single instance of [element] from this collection, if present.
 */
@IgnorableReturnValue
@Suppress("UNCHECKED_CAST")
public inline fun <T> MutableCollection<out T>.remove(element: T): Boolean {
    return (this as MutableCollection<T>).remove(element)
}

/**
 * Removes all elements in [elements] from this collection.
 */
@IgnorableReturnValue
@Suppress("UNCHECKED_CAST")
public inline fun <T> MutableCollection<out T>.removeAll(elements: Collection<T>): Boolean {
    return (this as MutableCollection<T>).removeAll(elements)
}

/**
 * Retains only elements present in [elements].
 */
@IgnorableReturnValue
@Suppress("UNCHECKED_CAST")
public inline fun <T> MutableCollection<out T>.retainAll(elements: Collection<T>): Boolean {
    return (this as MutableCollection<T>).retainAll(elements)
}

/**
 * Adds [element] to this mutable collection.
 */
public inline operator fun <T> MutableCollection<in T>.plusAssign(element: T) {
    add(element)
}

/**
 * Adds all elements from [elements] to this mutable collection.
 */
public inline operator fun <T> MutableCollection<in T>.plusAssign(elements: Iterable<T>) {
    addAllIterable(this, elements)
}

/**
 * Adds all elements from [elements] to this mutable collection.
 */
public inline operator fun <T> MutableCollection<in T>.plusAssign(elements: Array<T>) {
    addAllArray(this, elements)
}

/**
 * Adds all elements from [elements] to this mutable collection.
 */
public inline operator fun <T> MutableCollection<in T>.plusAssign(elements: Sequence<T>) {
    addAllSequence(this, elements)
}

/**
 * Removes one instance of [element] from this mutable collection.
 */
public inline operator fun <T> MutableCollection<in T>.minusAssign(element: T) {
    removeElement(this, element)
}

private fun <T> removeElement(destination: MutableCollection<in T>, element: T) {
    destination.remove(element)
}

/**
 * Removes all elements from [elements] in this mutable collection.
 */
public inline operator fun <T> MutableCollection<in T>.minusAssign(elements: Iterable<T>) {
    removeAllIterable(this, elements)
}

/**
 * Removes all elements from [elements] in this mutable collection.
 */
public inline operator fun <T> MutableCollection<in T>.minusAssign(elements: Array<T>) {
    removeAllArray(this, elements)
}

/**
 * Removes all elements from [elements] in this mutable collection.
 */
public inline operator fun <T> MutableCollection<in T>.minusAssign(elements: Sequence<T>) {
    removeAllSequence(this, elements)
}

/**
 * Adds all elements from [elements] to this mutable collection.
 */
@IgnorableReturnValue
public fun <T> MutableCollection<in T>.addAll(elements: Iterable<T>): Boolean {
    return addAllIterable(this, elements)
}

@Suppress("UNCHECKED_CAST")
private fun <T> addAllIterable(
    destination: MutableCollection<in T>,
    elements: Iterable<T>
): Boolean {
    if (elements is Collection) {
        val collection = elements as Collection<T>
        return addAllCollection(destination, collection)
    }

    var result = false
    for (item in elements) {
        if (destination.add(item)) result = true
    }
    return result
}

/**
 * Adds all elements from [elements] to this mutable collection.
 */
@IgnorableReturnValue
public fun <T> MutableCollection<in T>.addAll(elements: Sequence<T>): Boolean {
    return addAllSequence(this, elements)
}

private fun <T> addAllSequence(
    destination: MutableCollection<in T>,
    elements: Sequence<T>
): Boolean {
    var result = false
    for (item in elements) {
        if (destination.add(item)) result = true
    }
    return result
}

/**
 * Adds all elements from [elements] to this mutable collection.
 */
@IgnorableReturnValue
public fun <T> MutableCollection<in T>.addAll(elements: Array<out T>): Boolean {
    return addAllArray(this, elements)
}

private fun <T> addAllArray(
    destination: MutableCollection<in T>,
    elements: Array<out T>
): Boolean {
    return addAllCollection(destination, arrayToList(elements))
}

private fun <T> addAllCollection(
    destination: MutableCollection<in T>,
    elements: Collection<T>
): Boolean = destination.addAll(elements)

private fun <T> arrayToList(elements: Array<out T>): List<T> {
    val result = mutableListOf<T>()
    var index = 0
    while (index < elements.size) {
        result.add(elements[index])
        index++
    }
    return result
}

/**
 * Removes all elements in [elements] from this mutable collection.
 */
@IgnorableReturnValue
public fun <T> MutableCollection<in T>.removeAll(elements: Iterable<T>): Boolean {
    return removeAllIterable(this, elements)
}

@Suppress("UNCHECKED_CAST")
private fun <T> removeAllIterable(
    destination: MutableCollection<in T>,
    elements: Iterable<T>
): Boolean {
    if (elements is Collection) {
        return removeAllCollection(destination, elements as Collection<T>)
    }
    val list = mutableListOf<T>()
    for (element in elements) list.add(element)
    return removeAllCollection(destination, list)
}

/**
 * Removes all elements in [elements] from this mutable collection.
 */
@IgnorableReturnValue
public fun <T> MutableCollection<in T>.removeAll(elements: Sequence<T>): Boolean {
    return removeAllSequence(this, elements)
}

private fun <T> removeAllSequence(
    destination: MutableCollection<in T>,
    elements: Sequence<T>
): Boolean {
    val list = elements.toList()
    return list.isNotEmpty() && removeAllCollection(destination, list)
}

/**
 * Removes all elements in [elements] from this mutable collection.
 */
@IgnorableReturnValue
public fun <T> MutableCollection<in T>.removeAll(elements: Array<out T>): Boolean {
    return removeAllArray(this, elements)
}

private fun <T> removeAllArray(
    destination: MutableCollection<in T>,
    elements: Array<out T>
): Boolean {
    val list = arrayToList(elements)
    return list.size > 0 && removeAllCollection(destination, list)
}

private fun <T> removeAllCollection(
    destination: MutableCollection<in T>,
    elements: Collection<T>
): Boolean = destination.removeAll(elements)

/**
 * Retains only elements present in [elements].
 */
@IgnorableReturnValue
public fun <T> MutableCollection<in T>.retainAll(elements: Iterable<T>): Boolean {
    return retainAllIterable(this, elements)
}

@Suppress("UNCHECKED_CAST")
private fun <T> retainAllIterable(
    destination: MutableCollection<in T>,
    elements: Iterable<T>
): Boolean {
    if (elements is Collection) {
        return retainAllCollection(destination, elements as Collection<T>)
    }
    val list = mutableListOf<T>()
    for (element in elements) list.add(element)
    return retainAllCollection(destination, list)
}

/**
 * Retains only elements present in [elements].
 */
@IgnorableReturnValue
public fun <T> MutableCollection<in T>.retainAll(elements: Array<out T>): Boolean {
    return retainAllArray(this, elements)
}

private fun <T> retainAllArray(
    destination: MutableCollection<in T>,
    elements: Array<out T>
): Boolean {
    val list = arrayToList(elements)
    return if (list.size > 0) retainAllCollection(destination, list) else retainNothing(destination)
}

/**
 * Retains only elements present in [elements].
 */
@IgnorableReturnValue
public fun <T> MutableCollection<in T>.retainAll(elements: Sequence<T>): Boolean {
    return retainAllSequence(this, elements)
}

private fun <T> retainAllSequence(
    destination: MutableCollection<in T>,
    elements: Sequence<T>
): Boolean {
    val list = elements.toList()
    return if (list.isNotEmpty()) retainAllCollection(destination, list) else retainNothing(destination)
}

private fun <T> retainAllCollection(
    destination: MutableCollection<in T>,
    elements: Collection<T>
): Boolean = destination.retainAll(elements)

private fun retainNothing(destination: MutableCollection<*>): Boolean {
    val result = destination.size > 0
    destination.clear()
    return result
}
