/*
 * Copyright 2010-2024 JetBrains s.r.o. and Kotlin Programming Language contributors.
 * Licensed under the Apache License, Version 2.0.
 *
 * Derived from kotlin-stdlib libraries/stdlib/common/src/kotlin/collections/AbstractMutableMap.kt.
 */

package kotlin.collections

// KSP-930: the nominal AbstractMutableMap<K, V> declaration is source-backed
// here; KSP-1038 adds the native-wasm receiver implementation. The
// compiler-side shell remains the fallback for non-bundled contexts.

private class AbstractMutableMapKeys<K, V>(
    private val map: AbstractMutableMap<K, V>
) : AbstractMutableSet<K>() {
    override fun add(element: K): Boolean = throw UnsupportedOperationException("Add is not supported on keys")

    override fun clear() {
        map.clear()
    }

    override operator fun contains(element: K): Boolean = map.containsKey(element)

    override operator fun iterator(): MutableIterator<K> {
        val entryIterator = map.entries.iterator()
        return object : MutableIterator<K> {
            override fun hasNext(): Boolean = entryIterator.hasNext()
            override fun next(): K = entryIterator.next().key
            override fun remove() = entryIterator.remove()
        }
    }

    override fun remove(element: K): Boolean {
        if (map.containsKey(element)) {
            map.remove(element)
            return true
        }
        return false
    }

    override val size: Int get() = map.entries.size
}

private class AbstractMutableMapValues<K, V>(
    private val map: AbstractMutableMap<K, V>
) : AbstractMutableCollection<V>() {
    override fun add(element: V): Boolean = throw UnsupportedOperationException("Add is not supported on values")

    override fun clear() = map.clear()

    override operator fun contains(element: V): Boolean = map.containsValue(element)

    override operator fun iterator(): MutableIterator<V> {
        val entryIterator = map.entries.iterator()
        return object : MutableIterator<V> {
            override fun hasNext(): Boolean = entryIterator.hasNext()
            override fun next(): V = entryIterator.next().value
            override fun remove() = entryIterator.remove()
        }
    }

    override val size: Int get() = map.entries.size
}

/**
 * Provides a skeletal implementation of the MutableMap interface.
 */
public abstract class AbstractMutableMap<K, V> protected constructor() : AbstractMap<K, V>(), MutableMap<K, V> {
    @IgnorableReturnValue
    abstract override fun put(key: K, value: V): V?

    abstract override val entries: MutableSet<MutableMap.MutableEntry<K, V>>

    override fun putAll(from: Map<out K, V>) {
        for (entry in from.entries) {
            put(entry.key, entry.value)
        }
    }

    @IgnorableReturnValue
    override fun remove(key: K): V? {
        val iter = entries.iterator()
        while (iter.hasNext()) {
            val entry = iter.next()
            val k = entry.key
            if (key == k) {
                val value = entry.value
                iter.remove()
                return value
            }
        }
        return null
    }

    override fun clear() {
        entries.clear()
    }

    private var _keys: MutableSet<K>? = null
    private var _keysInitialized = false
    private fun getOrCreateKeys(): MutableSet<K> {
        if (!_keysInitialized) {
            _keys = AbstractMutableMapKeys(this)
            _keysInitialized = true
        }
        return _keys!!
    }

    override val keys: MutableSet<K>
        get() = getOrCreateKeys()

    private var _values: MutableCollection<V>? = null
    private var _valuesInitialized = false
    private fun getOrCreateValues(): MutableCollection<V> {
        if (!_valuesInitialized) {
            _values = AbstractMutableMapValues(this)
            _valuesInitialized = true
        }
        return _values!!
    }

    override val values: MutableCollection<V>
        get() = getOrCreateValues()
}
