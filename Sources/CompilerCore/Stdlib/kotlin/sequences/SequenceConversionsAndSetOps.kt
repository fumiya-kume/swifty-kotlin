package kotlin.sequences

import kotlin.internal.KsSymbolName

// KSP-443: Sequence 変換・集合演算を Kotlin 化

public inline fun <T> Sequence<T>.forEach(action: (T) -> Unit): Unit {
    for (element in this) action(element)
}

public inline fun <T> Sequence<T>.forEachIndexed(action: (index: Int, T) -> Unit): Unit {
    var index = 0
    for (item in this) action(checkIndexOverflow(index++), item)
}

public inline fun <T> Sequence<T>.find(predicate: (T) -> Boolean): T? {
    val iterator = this.iterator()
    while (iterator.hasNext()) {
        val element = iterator.next()
        if (predicate(element)) return element
    }
    return null
}

public inline fun <T> Sequence<T>.findLast(predicate: (T) -> Boolean): T? {
    var last: T? = null
    val iterator = this.iterator()
    while (iterator.hasNext()) {
        val element = iterator.next()
        if (predicate(element)) last = element
    }
    return last
}

@KsSymbolName("kk_sequence_to_list")
public fun <T> Sequence<T>.toList(): List<T> {
    val result = mutableListOf<T>()
    for (element in this) result.add(element)
    return result
}

public fun <T> Sequence<T>.toMutableList(): MutableList<T> {
    val result = mutableListOf<T>()
    for (element in this) result.add(element)
    return result
}

@KsSymbolName("kk_sequence_toCollection")
public fun <T, C : MutableCollection<in T>> Sequence<T>.toCollection(destination: C): C {
    for (element in this) destination.add(element)
    return destination
}

public fun <T> Sequence<T>.toSet(): Set<T> {
    val result = mutableSetOf<T>()
    for (element in this) result.add(element)
    return result
}

@KsSymbolName("kk_sequence_toMutableSet")
public fun <T> Sequence<T>.toMutableSet(): MutableSet<T> {
    val result = mutableSetOf<T>()
    for (element in this) result.add(element)
    return result
}

@KsSymbolName("kk_sequence_toHashSet")
public fun <T> Sequence<T>.toHashSet(): MutableSet<T> = toMutableSet()

@KsSymbolName("kk_sequence_toSortedSet")
public fun <T : Comparable<T>> Sequence<T>.toSortedSet(): MutableSet<T> {
    val sorted = toMutableList().sorted()
    val result = mutableSetOf<T>()
    for (element in sorted) result.add(element)
    return result
}

public fun <T, R> Sequence<Pair<T, R>>.unzip(): Pair<List<T>, List<R>> {
    val list1 = mutableListOf<T>()
    val list2 = mutableListOf<R>()
    for (pair in this) {
        list1.add(pair.first)
        list2.add(pair.second)
    }
    return Pair(list1.toList(), list2.toList())
}

@KsSymbolName("kk_sequence_union")
public fun <T> Sequence<T>.union(other: Iterable<T>): Set<T> {
    val result = toMutableSet()
    for (element in other) result.add(element)
    return result
}

public fun <T> Sequence<T>.union(other: Sequence<T>): Set<T> {
    val result = toMutableSet()
    for (element in other) result.add(element)
    return result
}

@KsSymbolName("kk_sequence_intersect")
public fun <T> Sequence<T>.intersect(other: Iterable<T>): Set<T> {
    val result = mutableSetOf<T>()
    val otherSet = mutableSetOf<T>()
    for (element in other) otherSet.add(element)
    for (element in this) {
        if (otherSet.contains(element)) result.add(element)
    }
    return result
}

@KsSymbolName("kk_sequence_intersect")
public fun <T> Sequence<T>.intersect(other: Sequence<T>): Set<T> {
    val result = mutableSetOf<T>()
    val otherSet = mutableSetOf<T>()
    for (element in other) otherSet.add(element)
    for (element in this) {
        if (otherSet.contains(element)) result.add(element)
    }
    return result
}

@KsSymbolName("kk_sequence_subtract")
public fun <T> Sequence<T>.subtract(other: Iterable<T>): Set<T> {
    val result = toMutableSet()
    for (element in other) result.remove(element)
    return result
}

public fun <T> Sequence<T>.subtract(other: Sequence<T>): Set<T> {
    val result = toMutableSet()
    for (element in other) result.remove(element)
    return result
}

@KsSymbolName("kk_sequence_plus_element")
public operator fun <T> Sequence<T>.plus(element: T): Sequence<T> {
    val source = this
    return object : Sequence<T> {
        override fun iterator(): Iterator<T> = object : Iterator<T> {
            val sourceIterator = source.iterator()
            var emittedElement = false

            override fun hasNext(): Boolean = sourceIterator.hasNext() || !emittedElement

            override fun next(): T {
                if (sourceIterator.hasNext()) return sourceIterator.next()
                if (!emittedElement) {
                    emittedElement = true
                    return element
                }
                throw NoSuchElementException()
            }
        }
    }
}

@KsSymbolName("kk_sequence_plus_element")
public fun <T> Sequence<T>.plusElement(element: T): Sequence<T> = plus(element)

@KsSymbolName("kk_sequence_plus")
public operator fun <T> Sequence<T>.plus(other: Iterable<T>): Sequence<T> {
    val source = this
    return object : Sequence<T> {
        override fun iterator(): Iterator<T> = object : Iterator<T> {
            val sourceIterator = source.iterator()
            var otherIterator: Iterator<T>? = null

            fun ensureOtherIterator() {
                if (otherIterator == null) otherIterator = other.iterator()
            }

            override fun hasNext(): Boolean {
                if (sourceIterator.hasNext()) return true
                ensureOtherIterator()
                return otherIterator!!.hasNext()
            }

            override fun next(): T {
                if (sourceIterator.hasNext()) return sourceIterator.next()
                ensureOtherIterator()
                if (!otherIterator!!.hasNext()) throw NoSuchElementException()
                return otherIterator!!.next()
            }
        }
    }
}

@KsSymbolName("kk_sequence_plus")
public operator fun <T> Sequence<T>.plus(other: Sequence<T>): Sequence<T> {
    val source = this
    return object : Sequence<T> {
        override fun iterator(): Iterator<T> = object : Iterator<T> {
            val sourceIterator = source.iterator()
            var otherIterator: Iterator<T>? = null

            fun ensureOtherIterator() {
                if (otherIterator == null) otherIterator = other.iterator()
            }

            override fun hasNext(): Boolean {
                if (sourceIterator.hasNext()) return true
                ensureOtherIterator()
                return otherIterator!!.hasNext()
            }

            override fun next(): T {
                if (sourceIterator.hasNext()) return sourceIterator.next()
                ensureOtherIterator()
                if (!otherIterator!!.hasNext()) throw NoSuchElementException()
                return otherIterator!!.next()
            }
        }
    }
}

@KsSymbolName("kk_sequence_plus")
public operator fun <T> Sequence<T>.plus(other: Array<out T>): Sequence<T> {
    val source = this
    val array = other
    return object : Sequence<T> {
        override fun iterator(): Iterator<T> = object : Iterator<T> {
            val sourceIterator = source.iterator()
            var index = 0

            override fun hasNext(): Boolean = sourceIterator.hasNext() || index < array.size

            override fun next(): T {
                if (sourceIterator.hasNext()) return sourceIterator.next()
                if (index < array.size) {
                    val result = array[index]
                    index = index + 1
                    return result
                }
                throw NoSuchElementException()
            }
        }
    }
}

private fun <T> Sequence<T>.minusRemoving(toRemove: List<Pair<T, Int>>): Sequence<T> {
    val source = this
    return object : Sequence<T> {
        override fun iterator(): Iterator<T> = object : Iterator<T> {
            val sourceIterator = source.iterator()
            val remaining = toRemove.toMutableList()
            var nextState = -2
            var nextItem: T? = null

            fun compute() {
                if (nextState == 0 || nextState == -1) return
                while (sourceIterator.hasNext()) {
                    val item = sourceIterator.next()
                    val index = remaining.indexOfFirst { it.first == item && it.second > 0 }
                    if (index >= 0) {
                        val pair = remaining[index]
                        remaining[index] = Pair(pair.first, pair.second - 1)
                    } else {
                        nextItem = item
                        nextState = 0
                        return
                    }
                }
                nextState = -1
            }

            override fun hasNext(): Boolean {
                compute()
                return nextState == 0
            }

            override fun next(): T {
                if (!hasNext()) throw NoSuchElementException()
                nextState = -2
                @Suppress("UNCHECKED_CAST")
                val result = nextItem as T
                nextItem = null
                return result
            }
        }
    }
}

@KsSymbolName("kk_sequence_minus")
public operator fun <T> Sequence<T>.minus(element: T): Sequence<T> {
    val source = this
    var removed = false
    return object : Sequence<T> {
        override fun iterator(): Iterator<T> = object : Iterator<T> {
            val sourceIterator = source.iterator()
            var nextState = -2
            var nextItem: T? = null

            fun compute() {
                if (nextState == 0 || nextState == -1) return
                while (sourceIterator.hasNext()) {
                    val item = sourceIterator.next()
                    if (!removed && item == element) {
                        removed = true
                    } else {
                        nextItem = item
                        nextState = 0
                        return
                    }
                }
                nextState = -1
            }

            override fun hasNext(): Boolean {
                compute()
                return nextState == 0
            }

            override fun next(): T {
                if (!hasNext()) throw NoSuchElementException()
                nextState = -2
                @Suppress("UNCHECKED_CAST")
                val result = nextItem as T
                nextItem = null
                return result
            }
        }
    }
}

private fun <T> buildRemovalCounts(other: Iterable<T>): MutableList<Pair<T, Int>> {
    val counts = mutableListOf<Pair<T, Int>>()
    for (e in other) {
        val index = counts.indexOfFirst { it.first == e }
        if (index >= 0) {
            val pair = counts[index]
            counts[index] = Pair(pair.first, pair.second + 1)
        } else {
            counts.add(Pair(e, 1))
        }
    }
    return counts
}

private fun <T> buildRemovalCounts(other: Sequence<T>): MutableList<Pair<T, Int>> {
    val counts = mutableListOf<Pair<T, Int>>()
    for (e in other) {
        val index = counts.indexOfFirst { it.first == e }
        if (index >= 0) {
            val pair = counts[index]
            counts[index] = Pair(pair.first, pair.second + 1)
        } else {
            counts.add(Pair(e, 1))
        }
    }
    return counts
}

private fun <T> buildRemovalCounts(other: Array<out T>): MutableList<Pair<T, Int>> {
    val counts = mutableListOf<Pair<T, Int>>()
    for (e in other) {
        val index = counts.indexOfFirst { it.first == e }
        if (index >= 0) {
            val pair = counts[index]
            counts[index] = Pair(pair.first, pair.second + 1)
        } else {
            counts.add(Pair(e, 1))
        }
    }
    return counts
}

public operator fun <T> Sequence<T>.minus(other: Iterable<T>): Sequence<T> =
    minusRemoving(buildRemovalCounts(other))

public operator fun <T> Sequence<T>.minus(other: Sequence<T>): Sequence<T> =
    minusRemoving(buildRemovalCounts(other))

public operator fun <T> Sequence<T>.minus(other: Array<out T>): Sequence<T> =
    minusRemoving(buildRemovalCounts(other))

@KsSymbolName("kk_sequence_minus")
public fun <T> Sequence<T>.minusElement(element: T): Sequence<T> = minus(element)

public fun <T> Sequence<T>.minus(predicate: (T) -> Boolean): Sequence<T> {
    val source = this
    return object : Sequence<T> {
        override fun iterator(): Iterator<T> = object : Iterator<T> {
            val sourceIterator = source.iterator()
            var nextState = -2
            var nextItem: T? = null

            fun compute() {
                if (nextState == 0 || nextState == -1) return
                while (sourceIterator.hasNext()) {
                    val item = sourceIterator.next()
                    if (!predicate(item)) {
                        nextItem = item
                        nextState = 0
                        return
                    }
                }
                nextState = -1
            }

            override fun hasNext(): Boolean {
                compute()
                return nextState == 0
            }

            override fun next(): T {
                if (!hasNext()) throw NoSuchElementException()
                nextState = -2
                @Suppress("UNCHECKED_CAST")
                val result = nextItem as T
                nextItem = null
                return result
            }
        }
    }
}

public fun <T> Sequence<T>.ifEmpty(defaultValue: () -> Sequence<T>): Sequence<T> {
    val source = this
    return object : Sequence<T> {
        override fun iterator(): Iterator<T> = object : Iterator<T> {
            var sourceIterator: Iterator<T>? = null
            var currentIterator: Iterator<T>? = null

            fun init() {
                if (currentIterator != null) return
                val iter = source.iterator()
                sourceIterator = iter
                if (iter.hasNext()) {
                    currentIterator = iter
                } else {
                    currentIterator = defaultValue().iterator()
                }
            }

            override fun hasNext(): Boolean {
                init()
                return currentIterator!!.hasNext()
            }

            override fun next(): T {
                init()
                return currentIterator!!.next()
            }
        }
    }
}

@KsSymbolName("kk_sequence_constrainOnce")
public fun <T> Sequence<T>.constrainOnce(): Sequence<T> {
    val source = this
    var used = false
    return object : Sequence<T> {
        override fun iterator(): Iterator<T> {
            if (used) throw IllegalStateException("Sequence can be consumed only once.")
            used = true
            return source.iterator()
        }
    }
}

public fun <T> Sequence<T>?.orEmpty(): Sequence<T> = this ?: emptySequence()

/**
 * Creates a grouping source from this sequence for later group-and-fold operations.
 */
public inline fun <T, K> Sequence<T>.groupingBy(crossinline keySelector: (T) -> K): Grouping<T, K> {
    val source = this
    return object : Grouping<T, K> {
        override fun sourceIterator(): Iterator<T> = source.iterator()
        override fun keyOf(element: T): K = keySelector(element)
    }
}
