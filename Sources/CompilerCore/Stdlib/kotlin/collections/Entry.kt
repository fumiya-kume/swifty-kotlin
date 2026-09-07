/*
 * Copyright 2010-2024 JetBrains s.r.o. and Kotlin Programming Language contributors.
 * Licensed under the Apache License, Version 2.0.
 *
 * Derived from kotlin-stdlib libraries/stdlib/src/kotlin/collections/Maps.kt.
 */

package kotlin.collections

/**
 * This method allows destructuring declarations when working with maps.
 */
@kotlin.internal.InlineOnly
public inline operator fun <K, V> Map.Entry<K, V>.component1(): K = this.key

/**
 * Returns the value component of the map entry.
 */
@kotlin.internal.InlineOnly
public inline operator fun <K, V> Map.Entry<K, V>.component2(): V = this.value

/**
 * Converts the entry to a [Pair] with the key as the first component and the
 * value as the second component.
 */
@kotlin.internal.InlineOnly
public inline fun <K, V> Map.Entry<K, V>.toPair(): Pair<K, V> = Pair(this.key, this.value)
