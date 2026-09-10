/*
 * Copyright 2010-2024 JetBrains s.r.o. and Kotlin Programming Language contributors.
 * Licensed under the Apache License, Version 2.0.
 *
 * Derived from kotlin-stdlib libraries/stdlib/src/kotlin/collections/Collections.kt.
 */

package kotlin.collections

/**
 * An iterator over a collection that supports traversing the collection in both directions.
 */
public interface ListIterator<out T> : Iterator<T> {
    public override fun next(): T

    public override fun hasNext(): Boolean

    public fun hasPrevious(): Boolean

    public fun previous(): T

    public fun nextIndex(): Int

    public fun previousIndex(): Int
}
