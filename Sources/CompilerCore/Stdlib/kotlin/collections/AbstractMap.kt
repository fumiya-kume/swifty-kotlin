/*
 * Copyright 2010-2024 JetBrains s.r.o. and Kotlin Programming Language contributors.
 * Licensed under the Apache License, Version 2.0.
 *
 * Derived from kotlin-stdlib libraries/stdlib/src/kotlin/collections/AbstractMap.kt.
 */

package kotlin.collections

import kotlin.internal.KsSymbolName

// KSP-928: the nominal AbstractMap declaration and its skeletal read-only
// operations are source-backed. Map allocation, entry materialization, and
// shared collection runtime bridges remain compiler/runtime-owned.

private fun <K, V> abstractMapKeys(entries: Set<Map.Entry<K, V>>): Set<K> {
    val result = mutableSetOf<K>()
    for (entry in entries) {
        result.add(entry.key)
    }
    return result
}

private fun <K, V> abstractMapValues(entries: Set<Map.Entry<K, V>>): Collection<V> {
    val result = mutableListOf<V>()
    for (entry in entries) {
        result.add(entry.value)
    }
    return result
}

@KsSymbolName("__kk_map_entries")
private external fun abstractMapEntries(map: Any?): Set<Map.Entry<Any?, Any?>>

/**
 * Provides a skeletal implementation of the read-only [Map] interface.
 */
public abstract class AbstractMap<K, out V> protected constructor() : Map<K, V> {
    protected abstract val entries: Set<Map.Entry<K, V>>

    override fun containsKey(key: K): Boolean {
        for (entry in entries) {
            if (entry.key == key) return true
        }
        return false
    }

    override fun containsValue(value: @UnsafeVariance V): Boolean {
        for (entry in entries) {
            if (entry.value == value) return true
        }
        return false
    }

    override operator fun get(key: K): V? {
        for (entry in entries) {
            if (entry.key == key) return entry.value
        }
        return null
    }

    override val size: Int
        get() = entries.size

    override fun isEmpty(): Boolean = entries.size == 0

    override val keys: Set<K>
        get() = abstractMapKeys(entries)

    override val values: Collection<V>
        get() = abstractMapValues(entries)

    override fun equals(other: Any?): Boolean {
        if (other === this) return true
        if (other is AbstractMap<*, *>) {
            if (entries.size != other.entries.size) return false
            for (entry in entries) {
                var found = false
                for (otherEntry in other.entries) {
                    if ((entry.key as Any?) == (otherEntry.key as Any?)
                        && (entry.value as Any?) == (otherEntry.value as Any?)) {
                        found = true
                        break
                    }
                }
                if (!found) return false
            }
            return true
        }
        if (other !is Map<*, *>) return false
        val otherEntries = abstractMapEntries(other)
        if (entries.size != otherEntries.size) return false
        for (entry in entries) {
            var found = false
            for (otherEntry in otherEntries) {
                if ((entry.key as Any?) == otherEntry.key
                    && (entry.value as Any?) == otherEntry.value) {
                    found = true
                    break
                }
            }
            if (!found) return false
        }
        return true
    }

    override fun hashCode(): Int {
        var result = 0
        for (entry in entries) {
            result += entry.key.hashCode() xor entry.value.hashCode()
        }
        return result
    }

    override fun toString(): String {
        var result = "{"
        var first = true
        for (entry in entries) {
            if (!first) result += ", "
            result += mapValueToString(entry.key) + "=" + mapValueToString(entry.value)
            first = false
        }
        return result + "}"
    }

    private fun mapValueToString(value: Any?): String =
        if (value === this) "(this Map)" else if (value == null) "null" else "$value"
}
