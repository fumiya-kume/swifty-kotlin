package kotlin.sequences

import kotlin.collections.IndexedValue

// MIGRATION-SEQ-002 / KSP-441
// Core higher-order transform functions for source-backed Sequence pipelines.

public fun <T, R> Sequence<T>.map(transform: (T) -> R): Sequence<R> {
    val source = this
    return object : Sequence<R> {
        override fun iterator(): Iterator<R> = object : Iterator<R> {
            val sourceIterator = source.iterator()
            override fun hasNext(): Boolean = sourceIterator.hasNext()
            override fun next(): R = transform(sourceIterator.next())
        }
    }
}

public fun <T, R> Sequence<T>.mapIndexed(transform: (Int, T) -> R): Sequence<R> {
    val source = this
    return object : Sequence<R> {
        override fun iterator(): Iterator<R> = object : Iterator<R> {
            val sourceIterator = source.iterator()
            var index = 0
            override fun hasNext(): Boolean = sourceIterator.hasNext()
            override fun next(): R {
                if (!sourceIterator.hasNext()) throw NoSuchElementException()
                val result = transform(index, sourceIterator.next())
                index = index + 1
                return result
            }
        }
    }
}

public fun <T, R : Any> Sequence<T>.mapNotNull(transform: (T) -> R?): Sequence<R> {
    val source = this
    return object : Sequence<R> {
        override fun iterator(): Iterator<R> = object : Iterator<R> {
            val sourceIterator = source.iterator()
            var nextState = -2
            var nextItem: R? = null

            override fun hasNext(): Boolean {
                if (nextState == -1) return false
                if (nextState == 0) return true
                while (sourceIterator.hasNext()) {
                    val item = sourceIterator.next()
                    val transformed = transform(item)
                    if (transformed != null) {
                        nextItem = transformed
                        nextState = 0
                        return true
                    }
                }
                nextState = -1
                return false
            }

            override fun next(): R {
                if (!hasNext()) throw NoSuchElementException()
                nextState = -2
                @Suppress("UNCHECKED_CAST")
                val result = nextItem as R
                nextItem = null
                return result
            }
        }
    }
}

public fun <T> Sequence<T>.filter(predicate: (T) -> Boolean): Sequence<T> {
    val source = this
    return object : Sequence<T> {
        override fun iterator(): Iterator<T> = object : Iterator<T> {
            val sourceIterator = source.iterator()
            var nextState = -2
            var nextItem: T? = null

            override fun hasNext(): Boolean {
                if (nextState == -1) return false
                if (nextState == 0) return true
                while (sourceIterator.hasNext()) {
                    val item = sourceIterator.next()
                    if (predicate(item)) {
                        nextItem = item
                        nextState = 0
                        return true
                    }
                }
                nextState = -1
                return false
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

public fun <T> Sequence<T>.filterNot(predicate: (T) -> Boolean): Sequence<T> {
    val source = this
    return object : Sequence<T> {
        override fun iterator(): Iterator<T> = object : Iterator<T> {
            val sourceIterator = source.iterator()
            var nextState = -2
            var nextItem: T? = null

            override fun hasNext(): Boolean {
                if (nextState == -1) return false
                if (nextState == 0) return true
                while (sourceIterator.hasNext()) {
                    val item = sourceIterator.next()
                    if (!predicate(item)) {
                        nextItem = item
                        nextState = 0
                        return true
                    }
                }
                nextState = -1
                return false
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

public fun <T> Sequence<T>.filterIndexed(predicate: (Int, T) -> Boolean): Sequence<T> {
    val source = this
    return object : Sequence<T> {
        override fun iterator(): Iterator<T> = object : Iterator<T> {
            val sourceIterator = source.iterator()
            var index = 0
            var nextState = -2
            var nextItem: T? = null

            override fun hasNext(): Boolean {
                if (nextState == -1) return false
                if (nextState == 0) return true
                while (sourceIterator.hasNext()) {
                    val item = sourceIterator.next()
                    if (predicate(index, item)) {
                        nextItem = item
                        nextState = 0
                        index = index + 1
                        return true
                    }
                    index = index + 1
                }
                nextState = -1
                return false
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

public fun <T> Sequence<T>.onEach(action: (T) -> Unit): Sequence<T> {
    val source = this
    return object : Sequence<T> {
        override fun iterator(): Iterator<T> = object : Iterator<T> {
            val sourceIterator = source.iterator()
            override fun hasNext(): Boolean = sourceIterator.hasNext()
            override fun next(): T {
                val item = sourceIterator.next()
                action(item)
                return item
            }
        }
    }
}

public fun <T> Sequence<T>.onEachIndexed(action: (Int, T) -> Unit): Sequence<T> {
    val source = this
    return object : Sequence<T> {
        override fun iterator(): Iterator<T> = object : Iterator<T> {
            val sourceIterator = source.iterator()
            var index = 0
            override fun hasNext(): Boolean = sourceIterator.hasNext()
            override fun next(): T {
                val item = sourceIterator.next()
                action(index, item)
                index = index + 1
                return item
            }
        }
    }
}

public fun <T, R : Any> Sequence<T>.mapIndexedNotNull(transform: (Int, T) -> R?): Sequence<R> {
    val source = this
    return object : Sequence<R> {
        override fun iterator(): Iterator<R> = object : Iterator<R> {
            val sourceIterator = source.iterator()
            var index = 0
            var nextState = -2
            var nextItem: R? = null

            fun compute() {
                if (nextState == 0 || nextState == -1) return
                while (sourceIterator.hasNext()) {
                    val item = sourceIterator.next()
                    val transformed = transform(index, item)
                    index = index + 1
                    if (transformed != null) {
                        nextItem = transformed
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

            override fun next(): R {
                if (!hasNext()) throw NoSuchElementException()
                nextState = -2
                @Suppress("UNCHECKED_CAST")
                val result = nextItem as R
                nextItem = null
                return result
            }
        }
    }
}

public fun <T, R> Sequence<T>.flatMap(transform: (T) -> Sequence<R>): Sequence<R> {
    val source = this
    return object : Sequence<R> {
        override fun iterator(): Iterator<R> = object : Iterator<R> {
            val sourceIterator = source.iterator()
            var currentIterator: Iterator<R> = emptySequence<R>().iterator()

            fun ensureNext() {
                while (!currentIterator.hasNext()) {
                    if (!sourceIterator.hasNext()) return
                    currentIterator = transform(sourceIterator.next()).iterator()
                }
            }

            override fun hasNext(): Boolean {
                ensureNext()
                return currentIterator.hasNext()
            }

            override fun next(): R {
                ensureNext()
                if (!currentIterator.hasNext()) throw NoSuchElementException()
                return currentIterator.next()
            }
        }
    }
}

public fun <T, R> Sequence<T>.flatMap(transform: (T) -> Iterable<R>): Sequence<R> {
    val source = this
    return object : Sequence<R> {
        override fun iterator(): Iterator<R> = object : Iterator<R> {
            val sourceIterator = source.iterator()
            var currentIterator: Iterator<R> = emptySequence<R>().iterator()

            fun ensureNext() {
                while (!currentIterator.hasNext()) {
                    if (!sourceIterator.hasNext()) return
                    currentIterator = transform(sourceIterator.next()).iterator()
                }
            }

            override fun hasNext(): Boolean {
                ensureNext()
                return currentIterator.hasNext()
            }

            override fun next(): R {
                ensureNext()
                if (!currentIterator.hasNext()) throw NoSuchElementException()
                return currentIterator.next()
            }
        }
    }
}

public fun <T, R> Sequence<T>.flatMapIndexed(transform: (Int, T) -> Sequence<R>): Sequence<R> {
    val source = this
    return object : Sequence<R> {
        override fun iterator(): Iterator<R> = object : Iterator<R> {
            val sourceIterator = source.iterator()
            var index = 0
            var currentIterator: Iterator<R> = emptySequence<R>().iterator()

            fun ensureNext() {
                while (!currentIterator.hasNext()) {
                    if (!sourceIterator.hasNext()) return
                    currentIterator = transform(index, sourceIterator.next()).iterator()
                    index = index + 1
                }
            }

            override fun hasNext(): Boolean {
                ensureNext()
                return currentIterator.hasNext()
            }

            override fun next(): R {
                ensureNext()
                if (!currentIterator.hasNext()) throw NoSuchElementException()
                return currentIterator.next()
            }
        }
    }
}

public fun <T, R> Sequence<T>.flatMapIndexed(transform: (Int, T) -> Iterable<R>): Sequence<R> {
    val source = this
    return object : Sequence<R> {
        override fun iterator(): Iterator<R> = object : Iterator<R> {
            val sourceIterator = source.iterator()
            var index = 0
            var currentIterator: Iterator<R> = emptySequence<R>().iterator()

            fun ensureNext() {
                while (!currentIterator.hasNext()) {
                    if (!sourceIterator.hasNext()) return
                    currentIterator = transform(index, sourceIterator.next()).iterator()
                    index = index + 1
                }
            }

            override fun hasNext(): Boolean {
                ensureNext()
                return currentIterator.hasNext()
            }

            override fun next(): R {
                ensureNext()
                if (!currentIterator.hasNext()) throw NoSuchElementException()
                return currentIterator.next()
            }
        }
    }
}

public fun <T> Sequence<Sequence<T>>.flatten(): Sequence<T> {
    val source = this
    return object : Sequence<T> {
        override fun iterator(): Iterator<T> = object : Iterator<T> {
            val sourceIterator = source.iterator()
            var currentIterator: Iterator<T> = emptySequence<T>().iterator()

            fun ensureNext() {
                while (!currentIterator.hasNext()) {
                    if (!sourceIterator.hasNext()) return
                    currentIterator = sourceIterator.next().iterator()
                }
            }

            override fun hasNext(): Boolean {
                ensureNext()
                return currentIterator.hasNext()
            }

            override fun next(): T {
                ensureNext()
                if (!currentIterator.hasNext()) throw NoSuchElementException()
                return currentIterator.next()
            }
        }
    }
}

public fun <T> Sequence<T>.withIndex(): Sequence<IndexedValue<T>> =
    mapIndexed<T, IndexedValue<T>> { index, value -> IndexedValue(index, value) }

public fun <T : Any> Sequence<T?>.filterNotNull(): Sequence<T> {
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
                    if (item != null) {
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

public fun <T : Any> Sequence<T?>.requireNoNulls(): Sequence<T> {
    val source = this
    return object : Sequence<T> {
        override fun iterator(): Iterator<T> = object : Iterator<T> {
            val sourceIterator = source.iterator()

            override fun hasNext(): Boolean = sourceIterator.hasNext()

            override fun next(): T {
                val item = sourceIterator.next()
                if (item == null) throw IllegalArgumentException("null element found in sequence")
                @Suppress("UNCHECKED_CAST")
                return item as T
            }
        }
    }
}
