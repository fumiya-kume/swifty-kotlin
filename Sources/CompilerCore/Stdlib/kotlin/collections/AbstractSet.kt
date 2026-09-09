/*
 * Copyright 2010-2024 JetBrains s.r.o. and Kotlin Programming Language contributors.
 * Licensed under the Apache License, Version 2.0.
 *
 * Derived from kotlin-stdlib libraries/stdlib/src/kotlin/collections/AbstractSet.kt.
 */

package kotlin.collections

// KSP-932: the nominal `AbstractSet<out E>` declaration is source-backed here;
// the compiler-side shell in `HeaderHelpers+SyntheticSetStubs.swift` remains
// the fallback for contexts without the bundled stdlib.

/**
 * Provides a skeletal implementation of the read-only [Set] interface.
 */
public abstract class AbstractSet<out E> protected constructor() : AbstractCollection<E>(), Set<E> {
    /**
     * Compares this set with another set using unordered structural equality.
     */
    override fun equals(other: Any?): Boolean {
        if (other === this) return true
        if (other !is Set<*>) return false
        var otherSize = 0
        for (element in other) {
            otherSize += 1
            var found = false
            for (ownElement in this) {
                if (ownElement == element) {
                    found = true
                    break
                }
            }
            if (!found) return false
        }
        return size == otherSize
    }

    /**
     * Returns the hash code value for this set.
     */
    override fun hashCode(): Int {
        var hashCode = 0
        for (element in this) {
            hashCode += element?.hashCode() ?: 0
        }
        return hashCode
    }
}
