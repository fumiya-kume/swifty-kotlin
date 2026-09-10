/*
 * Copyright 2010-2024 JetBrains s.r.o. and Kotlin Programming Language contributors.
 * Licensed under the Apache License, Version 2.0.
 *
 * Derived from kotlin-stdlib libraries/stdlib/native-wasm/src/kotlin/collections/HashMap.kt.
 */

package kotlin.collections

import kotlin.internal.KsSymbolName
import kotlin.internal.__valuesEqual

// KSP-1055: HashMap receiver members are source-backed.

private fun <K, V> __hashMapKeys(map: Map<K, V>): MutableSet<K> {
    val result = mutableSetOf<K>()
    for (entry in map.entries) {
        result.add(entry.key)
    }
    return result
}

private fun <K, V> __hashMapValues(map: Map<K, V>): MutableCollection<V> {
    val result = mutableListOf<V>()
    for (entry in map.entries) {
        result.add(entry.value)
    }
    return result
}

public class HashMap<K, V> : MutableMap<K, V> {
    constructor()
    constructor(initialCapacity: Int)
    constructor(initialCapacity: Int, loadFactor: Float)
    constructor(original: Map<out K, V>)

    @KsSymbolName("kk_map_size")
    private external fun __hashMapSize(): Int

    @KsSymbolName("kk_map_is_empty")
    private external fun __hashMapIsEmpty(): Boolean

    @KsSymbolName("__kk_map_get")
    private external fun __hashMapGet(key: K): V?

    @KsSymbolName("__kk_mutable_map_put")
    private external fun __hashMapPut(key: K, value: V): V?

    @KsSymbolName("__kk_mutable_map_remove")
    private external fun __hashMapRemove(key: K): V?

    @KsSymbolName("__kk_mutable_map_clear")
    private external fun __hashMapClear(): Unit

    @KsSymbolName("__kk_map_entries")
    private external fun __hashMapEntries(): MutableSet<MutableMap.MutableEntry<K, V>>

    @KsSymbolName("__kk_builder_map_freeze")
    private external fun __hashMapFreeze(): Map<K, V>

    @PublishedApi
    internal fun build(): Map<K, V> = __hashMapFreeze()

    override fun clear() {
        __hashMapClear()
    }

    override fun containsKey(key: K): Boolean {
        for (entry in entries) {
            if (__valuesEqual(entry.key, key)) return true
        }
        return false
    }

    override fun containsValue(value: V): Boolean {
        for (entry in entries) {
            if (__valuesEqual(entry.value, value)) return true
        }
        return false
    }

    override val entries: MutableSet<MutableMap.MutableEntry<K, V>>
        get() = __hashMapEntries()

    override fun equals(other: Any?): Boolean {
        if (other === this) return true
        if (other !is Map<*, *>) return false
        val thisEntries = entries
        val otherEntries = other.entries
        if (thisEntries.size != otherEntries.size) return false

        for (entry in thisEntries) {
            var found = false
            for (otherEntry in otherEntries) {
                if (__valuesEqual(entry.key, otherEntry.key)) {
                    if (!__valuesEqual(entry.value, otherEntry.value)) return false
                    found = true
                    break
                }
            }
            if (!found) return false
        }
        return true
    }

    override operator fun get(key: K): V? = __hashMapGet(key)

    override fun hashCode(): Int {
        var result = 0
        for (entry in entries) {
            val keyHash = entry.key?.hashCode() ?: 0
            val valueHash = entry.value?.hashCode() ?: 0
            result += keyHash xor valueHash
        }
        return result
    }

    override fun isEmpty(): Boolean = __hashMapIsEmpty()

    override val keys: MutableSet<K>
        get() = __hashMapKeys(this)

    @IgnorableReturnValue
    override fun put(key: K, value: V): V? = __hashMapPut(key, value)

    override fun putAll(from: Map<out K, V>) {
        for (entry in from.entries) {
            put(entry.key, entry.value)
        }
    }

    @IgnorableReturnValue
    override fun remove(key: K): V? = __hashMapRemove(key)

    override val size: Int
        get() = __hashMapSize()

    override fun toString(): String {
        val builder = StringBuilder()
        builder.append("{")
        var first = true
        for (entry in entries) {
            if (!first) builder.append(", ")
            first = false
            if (entry.key === this) {
                builder.append("(this Map)")
            } else {
                builder.append(entry.key?.toString() ?: "null")
            }
            builder.append("=")
            if (entry.value === this) {
                builder.append("(this Map)")
            } else {
                builder.append(entry.value?.toString() ?: "null")
            }
        }
        builder.append("}")
        return builder.toString()
    }

    override val values: MutableCollection<V>
        get() = __hashMapValues(this)
}
