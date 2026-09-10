/*
 * Copyright 2010-2024 JetBrains s.r.o. and Kotlin Programming Language contributors.
 * Licensed under the Apache License, Version 2.0.
 *
 * Derived from kotlin-stdlib libraries/stdlib/native-wasm/src/kotlin/collections/HashMap.kt.
 */

package kotlin.collections

import kotlin.internal.KsSymbolName

@KsSymbolName("__kk_mutable_map_entry_setValue")
private external fun <K, V> __kkMutableMapEntrySetValue(
    entry: MutableMap.MutableEntry<K, V>,
    newValue: V
): V

/**
 * Replaces the value associated with this entry and returns the previous value.
 */
@kotlin.internal.InlineOnly
@IgnorableReturnValue
public inline fun <K, V> MutableMap.MutableEntry<K, V>.setValue(newValue: V): V =
    __kkMutableMapEntrySetValue(this, newValue)
