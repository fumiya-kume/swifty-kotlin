/*
 * Copyright 2016-2024 JetBrains s.r.o. and Kotlin Programming Language contributors.
 * Licensed under the Apache License, Version 2.0.
 *
 * Derived from kotlinx.coroutines channel builder APIs.
 */

package kotlinx.coroutines.channels

import kotlin.internal.KsSymbolName
import kotlinx.coroutines.CoroutineScope

// KSP-1543: ProducerScope is the receiver exposed by channelFlow and
// callbackFlow. The object is backed by the runtime channel created for each
// collection; the member operations below keep the public Kotlin shape while
// retaining the channel ABI at the boundary.

@JvmInline
public value class ChannelResult<out T> internal constructor(internal val token: Int) {
    public val isSuccess: Boolean
        get() = token == 0

    public val isFailure: Boolean
        get() = !isSuccess

    public val isClosed: Boolean
        get() = token == 1 || token == 2
}

public interface SendChannel<in E> {
    @KsSymbolName("kk_channel_send")
    public external suspend fun send(element: E): Unit

    @KsSymbolName("kk_channel_try_send")
    public external fun trySend(element: E): ChannelResult<Unit>

    @KsSymbolName("kk_channel_close")
    public external fun close(): Boolean
}

public interface ProducerScope<in E> : CoroutineScope, SendChannel<E>
