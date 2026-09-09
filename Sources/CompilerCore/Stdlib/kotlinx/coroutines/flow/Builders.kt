/*
 * Copyright 2016-2024 JetBrains s.r.o. and Kotlin Programming Language contributors.
 * Licensed under the Apache License, Version 2.0.
 *
 * Derived from kotlinx.coroutines <kotlinx-coroutines-core/common/src/flow/Builders.kt>.
 */

package kotlinx.coroutines.flow

import kotlin.internal.KsSymbolName
import kotlinx.coroutines.channels.ProducerScope

// MIGRATION-FLOW-001 (KSP-674)
// flowOf / emptyFlow / Iterable.asFlow migrated from dedicated runtime bridges
// (kk_flow_of / kk_flow_empty / kk_flow_as_flow) to Kotlin source composed from
// the retained cold-Flow core: `flow { }` (kk_flow_create) + `emit` (kk_flow_emit).

public fun <T> flowOf(vararg elements: T): Flow<T> = flow {
    for (element in elements) {
        emit(element)
    }
}

public fun <T> emptyFlow(): Flow<T> = flow {
}

public fun <T> Iterable<T>.asFlow(): Flow<T> {
    val source = this
    return flow {
        for (element in source) {
            emit(element)
        }
    }
}

// KSP-1543: Unlike the cold `flow` builder, these builders expose a real
// ProducerScope backed by a per-collection runtime channel.
@KsSymbolName("kk_channel_flow_create")
public external fun <T> channelFlow(block: suspend ProducerScope<T>.() -> Unit): Flow<T>

@KsSymbolName("kk_callback_flow_create")
public external fun <T> callbackFlow(block: suspend ProducerScope<T>.() -> Unit): Flow<T>
