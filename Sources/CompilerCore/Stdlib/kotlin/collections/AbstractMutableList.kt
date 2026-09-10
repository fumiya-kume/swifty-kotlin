/*
 * Copyright 2010-2024 JetBrains s.r.o. and Kotlin Programming Language contributors.
 * Licensed under the Apache License, Version 2.0.
 *
 * Derived from kotlin-stdlib native-wasm/src/kotlin/collections/AbstractMutableList.kt.
 */

package kotlin.collections

// KSP-929: the nominal `AbstractMutableList<E>` declaration is source-backed
// here; the compiler-side shell remains the fallback for non-bundled contexts.
// KSP-1036: the default list members are also implemented here, following the
// Kotlin 2.3.10 native-wasm contract.

/**
 * Provides a skeletal implementation of the [MutableList] interface.
 */
public abstract class AbstractMutableList<E> protected constructor() : AbstractMutableCollection<E>(), MutableList<E> {
    /**
     * The number of structural modifications observed by iterators.
     * Concrete implementations update this counter when they mutate storage.
     */
    protected var modCount: Int = 0

    // These storage primitives are redeclared by the platform implementation
    // because concrete mutable list implementations must provide them.
    abstract override fun get(index: Int): E
    abstract override fun add(index: Int, element: E)

    @IgnorableReturnValue
    abstract override fun removeAt(index: Int): E

    @IgnorableReturnValue
    abstract override fun set(index: Int, element: E): E

    @IgnorableReturnValue
    override fun add(element: E): Boolean {
        add(size, element)
        return true
    }

    @IgnorableReturnValue
    override fun addAll(index: Int, elements: Collection<E>): Boolean {
        abstractMutableListCheckPositionIndex(index, size)

        var insertionIndex = index
        var changed = false
        for (element in elements) {
            add(insertionIndex, element)
            insertionIndex += 1
            changed = true
        }
        return changed
    }

    override fun clear() {
        removeRange(0, size)
    }

    @IgnorableReturnValue
    override fun removeAll(elements: Collection<E>): Boolean {
        var changed = false
        val iterator = iterator()
        while (iterator.hasNext()) {
            if (elements.contains(iterator.next())) {
                iterator.remove()
                changed = true
            }
        }
        return changed
    }

    @IgnorableReturnValue
    override fun retainAll(elements: Collection<E>): Boolean {
        var changed = false
        val iterator = iterator()
        while (iterator.hasNext()) {
            if (!elements.contains(iterator.next())) {
                iterator.remove()
                changed = true
            }
        }
        return changed
    }

    override fun iterator(): MutableIterator<E> = IteratorImpl(this)

    override fun contains(element: E): Boolean = indexOf(element) >= 0

    override fun indexOf(element: E): Int {
        var index = 0
        while (index < size) {
            if (get(index) == element) return index
            index += 1
        }
        return -1
    }

    override fun lastIndexOf(element: E): Int {
        var index = size - 1
        while (index >= 0) {
            if (get(index) == element) return index
            index -= 1
        }
        return -1
    }

    override fun listIterator(): MutableListIterator<E> = listIterator(0)

    override fun listIterator(index: Int): MutableListIterator<E> = ListIteratorImpl(this, index)

    override fun subList(fromIndex: Int, toIndex: Int): MutableList<E> = SubList(this, fromIndex, toIndex)

    /**
     * Removes the range starting at [fromIndex] and ending before [toIndex].
     */
    protected open fun removeRange(fromIndex: Int, toIndex: Int) {
        val iterator = listIterator(fromIndex)
        repeat(toIndex - fromIndex) {
            iterator.next()
            iterator.remove()
        }
    }

    override fun equals(other: Any?): Boolean {
        if (other === this) return true
        if (other !is List<*>) return false

        return abstractMutableListOrderedEquals(this, other)
    }

    override fun hashCode(): Int = abstractMutableListOrderedHashCode(this)

    private open class IteratorImpl<T>(private val list: AbstractMutableList<T>) : MutableIterator<T> {
        var index = 0
        var last = -1
        var expectedModCount = list.currentModCount()

        override fun hasNext(): Boolean = index < list.size

        override fun next(): T {
            checkForComodification()
            if (!hasNext()) throw NoSuchElementException()
            last = index
            index += 1
            return list.get(last)
        }

        override fun remove() {
            checkForComodification()
            check(last != -1) { "Call next() or previous() before removing element from the iterator." }

            list.removeAt(last)
            index = last
            last = -1
            expectedModCount = list.currentModCount()
        }

        fun checkForComodification() {
            if (list.currentModCount() != expectedModCount) throw ConcurrentModificationException()
        }
    }

    private class ListIteratorImpl<T>(
        private val list: AbstractMutableList<T>,
        index: Int
    ) : MutableListIterator<T> {
        private var cursor = 0
        private var last = -1
        private var expectedModCount = list.currentModCount()

        init {
            abstractMutableListCheckPositionIndex(index, list.size)
            cursor = index
        }

        override fun hasNext(): Boolean = cursor < list.size

        override fun next(): T {
            checkForComodification()
            if (!hasNext()) throw NoSuchElementException()
            last = cursor
            cursor += 1
            return list.get(last)
        }

        override fun remove() {
            checkForComodification()
            check(last != -1) { "Call next() or previous() before removing element from the iterator." }

            list.removeAt(last)
            cursor = last
            last = -1
            expectedModCount = list.currentModCount()
        }

        override fun hasPrevious(): Boolean = cursor > 0

        override fun nextIndex(): Int = cursor

        override fun previous(): T {
            checkForComodification()
            if (!hasPrevious()) throw NoSuchElementException()

            cursor -= 1
            last = cursor
            return list.get(last)
        }

        override fun previousIndex(): Int = cursor - 1

        override fun add(element: T) {
            checkForComodification()
            list.add(cursor, element)
            cursor += 1
            last = -1
            expectedModCount = list.currentModCount()
        }

        override fun set(element: T) {
            checkForComodification()
            check(last != -1) { "Call next() or previous() before updating element value with the iterator." }
            list.set(last, element)
            expectedModCount = list.currentModCount()
        }

        private fun checkForComodification() {
            if (list.currentModCount() != expectedModCount) throw ConcurrentModificationException()
        }
    }

    private class SubList<E>(
        private val list: AbstractMutableList<E>,
        private val fromIndex: Int,
        toIndex: Int
    ) : AbstractMutableList<E>() {
        private var subListSize: Int = 0

        init {
            abstractMutableListCheckRangeIndexes(fromIndex, toIndex, list.size)
            subListSize = toIndex - fromIndex
            modCount = list.modCount
        }

        override fun add(index: Int, element: E) {
            checkForComodification()
            abstractMutableListCheckPositionIndex(index, subListSize)

            list.add(fromIndex + index, element)
            subListSize += 1
            modCount = list.modCount
        }

        override fun get(index: Int): E {
            checkForComodification()
            abstractMutableListCheckElementIndex(index, subListSize)
            return list.get(fromIndex + index)
        }

        override fun removeAt(index: Int): E {
            checkForComodification()
            abstractMutableListCheckElementIndex(index, subListSize)

            val result = list.removeAt(fromIndex + index)
            subListSize -= 1
            modCount = list.modCount
            return result
        }

        override fun set(index: Int, element: E): E {
            checkForComodification()
            abstractMutableListCheckElementIndex(index, subListSize)
            return list.set(fromIndex + index, element)
        }

        override fun removeRange(fromIndex: Int, toIndex: Int) {
            checkForComodification()
            abstractMutableListCheckRangeIndexes(fromIndex, toIndex, subListSize)
            list.removeRange(this.fromIndex + fromIndex, this.fromIndex + toIndex)
            subListSize -= toIndex - fromIndex
            modCount = list.modCount
        }

        override val size: Int
            get() {
                checkForComodification()
                return subListSize
            }

        override fun iterator(): MutableIterator<E> {
            checkForComodification()
            return IteratorImpl(this)
        }

        override fun listIterator(index: Int): MutableListIterator<E> {
            checkForComodification()
            return ListIteratorImpl(this, index)
        }

        private fun checkForComodification() {
            if (list.modCount != modCount) throw ConcurrentModificationException()
        }
    }

    private fun currentModCount(): Int = modCount
}

private fun abstractMutableListCheckElementIndex(index: Int, size: Int) {
    if (index < 0 || index >= size) {
        throw IndexOutOfBoundsException("index: $index, size: $size")
    }
}

private fun abstractMutableListCheckPositionIndex(index: Int, size: Int) {
    if (index < 0 || index > size) {
        throw IndexOutOfBoundsException("index: $index, size: $size")
    }
}

private fun abstractMutableListCheckRangeIndexes(fromIndex: Int, toIndex: Int, size: Int) {
    if (fromIndex < 0 || toIndex > size) {
        throw IndexOutOfBoundsException("fromIndex: $fromIndex, toIndex: $toIndex, size: $size")
    }
    if (fromIndex > toIndex) {
        throw IllegalArgumentException("fromIndex: $fromIndex > toIndex: $toIndex")
    }
}

private fun abstractMutableListOrderedHashCode(collection: Collection<*>): Int {
    var hashCode = 1
    for (element in collection) {
        hashCode = 31 * hashCode + (element?.hashCode() ?: 0)
    }
    return hashCode
}

private fun abstractMutableListOrderedEquals(collection: Collection<*>, other: Collection<*>): Boolean {
    if (collection.size != other.size) return false

    val otherIterator = other.iterator()
    for (element in collection) {
        if (element != otherIterator.next()) return false
    }
    return true
}
