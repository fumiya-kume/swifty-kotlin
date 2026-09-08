/*
 * Copyright 2010-2024 JetBrains s.r.o. and Kotlin Programming Language contributors.
 * Licensed under the Apache License, Version 2.0.
 *
 * Derived from kotlin-stdlib <libraries/stdlib/src/kotlin/collections/AbstractIterator.kt>.
 */

package kotlin.collections

import kotlin.internal.KsSymbolName

/**
 * An iterator over a sequence of elements.
 */
public interface Iterator<out T> {
    /**
     * Returns true if the iteration has more elements.
     */
    @KsSymbolName("kk_iterator_hasNext")
    public operator fun hasNext(): Boolean

    /**
     * Returns the next element in the iteration, or throws [NoSuchElementException]
     * if the iteration has no more elements.
     */
    @KsSymbolName("kk_iterator_next")
    public operator fun next(): T
}

/**
 * A base class to simplify implementing iterators so that implementations only have to implement [computeNext]
 * to implement the iterator, calling [done] when the iteration is complete.
 */
public abstract class AbstractIterator<T> : Iterator<T> {
    private var state = State.NotReady
    private var nextValue: T? = null

    override fun hasNext(): Boolean {
        require(state != State.Failed)
        return when (state) {
            State.Done -> false
            State.Ready -> true
            else -> tryToComputeNext()
        }
    }

    override fun next(): T {
        if (!hasNext()) throw NoSuchElementException()
        state = State.NotReady
        @Suppress("UNCHECKED_CAST")
        val result = nextValue as T
        nextValue = null
        return result
    }

    private fun tryToComputeNext(): Boolean {
        state = State.Failed
        computeNext()
        return state == State.Ready
    }

    /**
     * Computes the next item in the iterator.
     *
     * This callback method should call one of these two methods:
     *
     * * [setNext] with the next value of the iteration
     * * [done] to indicate there are no more elements
     *
     * Failure to call either method will result in the iteration terminating with a failed state
     */
    protected abstract fun computeNext(): Unit

    /**
     * Sets the next value in the iteration, called from the [computeNext] function
     */
    protected fun setNext(value: T): Unit {
        nextValue = value
        state = State.Ready
    }

    /**
     * Sets the state to done so that the iteration terminates.
     */
    protected fun done() {
        state = State.Done
    }
}

private enum class State {
    Ready,
    NotReady,
    Done,
    Failed
}
