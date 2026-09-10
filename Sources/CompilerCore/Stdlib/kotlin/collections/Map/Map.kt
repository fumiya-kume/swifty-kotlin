/*
 * Copyright 2010-2025 JetBrains s.r.o. and Kotlin Programming Language contributors.
 * Use of this source code is governed by the Apache 2.0 license that can be found in the
 * license/LICENSE.txt file.
 */

package kotlin.collections

public interface Map<K, out V> {
    public val size: Int
    public val keys: Set<K>
    public val values: Collection<V>
    public val entries: Set<Map.Entry<K, V>>
    public fun isEmpty(): Boolean
    public operator fun get(key: K): V?
}
