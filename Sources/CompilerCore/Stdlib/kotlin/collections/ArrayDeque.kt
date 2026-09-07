package kotlin.collections

import kotlin.internal.KsSymbolName
import kotlin.internal.__valuesEqual

// KSP-625: ArrayDeque migrated to bundled Kotlin source.
// `first` / `last` / `isEmpty` / `toString` and the emptiness / bounds checks
// are Kotlin logic; only the ring-buffer mutation primitives stay in the
// runtime (`__kk_arraydeque_*`), because the element storage is a
// runtime-managed, GC-traced buffer.

@KsSymbolName("__kk_arraydeque_size")
private external fun <E> __kkArrayDequeSize(deque: ArrayDeque<E>): Int

@KsSymbolName("__kk_arraydeque_get")
private external fun <E> __kkArrayDequeGet(deque: ArrayDeque<E>, index: Int): E

@KsSymbolName("__kk_arraydeque_removeFirst")
private external fun <E> __kkArrayDequeRemoveFirst(deque: ArrayDeque<E>): E

@KsSymbolName("__kk_arraydeque_removeLast")
private external fun <E> __kkArrayDequeRemoveLast(deque: ArrayDeque<E>): E

/**
 * Resizable-array implementation of the deque data structure.
 */
public class ArrayDeque<E> {
    @KsSymbolName("__kk_arraydeque_new")
    public constructor()

    public val size: Int
        get() = __kkArrayDequeSize(this)

    public fun isEmpty(): Boolean = __kkArrayDequeSize(this) == 0

    public fun isNotEmpty(): Boolean = !isEmpty()

    @KsSymbolName("__kk_arraydeque_addFirst")
    public external fun addFirst(element: E): Unit

    @KsSymbolName("__kk_arraydeque_addLast")
    public external fun addLast(element: E): Unit

    public operator fun get(index: Int): E {
        val currentSize = __kkArrayDequeSize(this)
        if (index < 0 || index >= currentSize) {
            throw IndexOutOfBoundsException("index: $index, size: $currentSize")
        }
        return __kkArrayDequeGet(this, index)
    }

    public fun first(): E {
        if (__kkArrayDequeSize(this) == 0) throw NoSuchElementException("ArrayDeque is empty.")
        return __kkArrayDequeGet(this, 0)
    }

    public fun last(): E {
        val currentSize = __kkArrayDequeSize(this)
        if (currentSize == 0) throw NoSuchElementException("ArrayDeque is empty.")
        return __kkArrayDequeGet(this, currentSize - 1)
    }

    public fun firstOrNull(): E? = if (isEmpty()) null else first()

    public fun lastOrNull(): E? = if (isEmpty()) null else last()

    public fun removeFirst(): E {
        if (__kkArrayDequeSize(this) == 0) throw NoSuchElementException("ArrayDeque is empty.")
        return __kkArrayDequeRemoveFirst(this)
    }

    public fun removeLast(): E {
        if (__kkArrayDequeSize(this) == 0) throw NoSuchElementException("ArrayDeque is empty.")
        return __kkArrayDequeRemoveLast(this)
    }

    public fun removeFirstOrNull(): E? = if (isEmpty()) null else removeFirst()

    public fun removeLastOrNull(): E? = if (isEmpty()) null else removeLast()

    // MutableList and MutableCollection surface.
    @IgnorableReturnValue
    public fun add(element: E): Boolean {
        addLast(element)
        return true
    }

    public fun add(index: Int, element: E) {
        val currentSize = __kkArrayDequeSize(this)
        if (index < 0 || index > currentSize) {
            throw IndexOutOfBoundsException("index: $index, size: $currentSize")
        }
        if (index == 0) {
            addFirst(element)
            return
        }
        if (index == currentSize) {
            addLast(element)
            return
        }

        if (index <= currentSize / 2) {
            var moved = 0
            while (moved < index) {
                addLast(removeFirst())
                moved += 1
            }
            addFirst(element)
            while (moved > 0) {
                addFirst(removeLast())
                moved -= 1
            }
        } else {
            val suffixSize = currentSize - index
            var moved = 0
            while (moved < suffixSize) {
                addFirst(removeLast())
                moved += 1
            }
            addLast(element)
            while (moved > 0) {
                addLast(removeFirst())
                moved -= 1
            }
        }
    }

    @IgnorableReturnValue
    public fun addAll(elements: Collection<E>): Boolean = addAll(size, elements)

    @IgnorableReturnValue
    public fun addAll(index: Int, elements: Collection<E>): Boolean {
        val currentSize = __kkArrayDequeSize(this)
        if (index < 0 || index > currentSize) {
            throw IndexOutOfBoundsException("index: $index, size: $currentSize")
        }

        val pending = ArrayDeque<E>()
        val iterator = elements.iterator()
        while (iterator.hasNext()) {
            pending.addLast(iterator.next())
        }
        if (pending.isEmpty()) return false

        var targetIndex = index
        var pendingIndex = 0
        val pendingSize = pending.size
        while (pendingIndex < pendingSize) {
            add(targetIndex, pending[pendingIndex])
            targetIndex += 1
            pendingIndex += 1
        }
        return true
    }

    public operator fun contains(element: E): Boolean = indexOf(element) >= 0

    public fun indexOf(element: E): Int {
        var index = 0
        val currentSize = __kkArrayDequeSize(this)
        while (index < currentSize) {
            if (__valuesEqual(this[index], element)) return index
            index += 1
        }
        return -1
    }

    public fun lastIndexOf(element: E): Int {
        var index = __kkArrayDequeSize(this) - 1
        while (index >= 0) {
            if (__valuesEqual(this[index], element)) return index
            index -= 1
        }
        return -1
    }

    @IgnorableReturnValue
    public fun remove(element: E): Boolean {
        val index = indexOf(element)
        if (index < 0) return false
        removeAt(index)
        return true
    }

    @IgnorableReturnValue
    public fun removeAt(index: Int): E {
        val currentSize = __kkArrayDequeSize(this)
        if (index < 0 || index >= currentSize) {
            throw IndexOutOfBoundsException("index: $index, size: $currentSize")
        }
        if (index == 0) return removeFirst()
        if (index == currentSize - 1) return removeLast()

        if (index <= currentSize / 2) {
            var moved = 0
            while (moved < index) {
                addLast(removeFirst())
                moved += 1
            }
            val removed = removeFirst()
            while (moved > 0) {
                addFirst(removeLast())
                moved -= 1
            }
            return removed
        }

        val suffixSize = currentSize - index
        var moved = 0
        while (moved < suffixSize) {
            addFirst(removeLast())
            moved += 1
        }
        val removed = removeFirst()
        moved -= 1
        while (moved > 0) {
            addLast(removeFirst())
            moved -= 1
        }
        return removed
    }

    @IgnorableReturnValue
    public fun removeAll(elements: Collection<E>): Boolean {
        var modified = false
        var index = 0
        while (index < __kkArrayDequeSize(this)) {
            if (elements.contains(this[index])) {
                removeAt(index)
                modified = true
            } else {
                index += 1
            }
        }
        return modified
    }

    @IgnorableReturnValue
    public fun retainAll(elements: Collection<E>): Boolean {
        var modified = false
        var index = 0
        while (index < __kkArrayDequeSize(this)) {
            if (!elements.contains(this[index])) {
                removeAt(index)
                modified = true
            } else {
                index += 1
            }
        }
        return modified
    }

    public fun clear() {
        while (isNotEmpty()) {
            removeLast()
        }
    }

    public operator fun set(index: Int, element: E): E {
        val previous = removeAt(index)
        add(index, element)
        return previous
    }

    @Suppress("UNCHECKED_CAST")
    public fun <T> toArray(array: Array<T>): Array<T> {
        val currentSize = __kkArrayDequeSize(this)
        val resultSize = if (array.size >= currentSize) array.size else currentSize
        val result = if (array.size >= currentSize) {
            array
        } else {
            arrayOfNulls<Any?>(currentSize) as Array<T>
        }
        val writable = result as Array<Any?>
        var index = 0
        while (index < currentSize) {
            writable[index] = this[index]
            index += 1
        }
        if (resultSize > currentSize) {
            writable[currentSize] = null
        }
        return result
    }

    @Suppress("UNCHECKED_CAST")
    public fun toArray(): Array<Any?> = toArray(arrayOfNulls<Any?>(__kkArrayDequeSize(this)))

    override fun toString(): String {
        val builder = StringBuilder()
        builder.append("[")
        var index = 0
        val currentSize = __kkArrayDequeSize(this)
        while (index < currentSize) {
            if (index > 0) builder.append(", ")
            builder.append(__kkArrayDequeGet(this, index).toString())
            index += 1
        }
        builder.append("]")
        return builder.toString()
    }
}
