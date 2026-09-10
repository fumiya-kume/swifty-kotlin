/*
 * Copyright 2010-2024 JetBrains s.r.o. and Kotlin Programming Language contributors.
 * Licensed under the Apache License, Version 2.0.
 *
 * Derived from kotlin-stdlib libraries/stdlib/src/kotlin/coroutines/intrinsics/Intrinsics.kt
 * and kotlin-native/runtime/src/main/kotlin/kotlin/coroutines/intrinsics/IntrinsicsNative.kt.
 */

package kotlin.coroutines.intrinsics

import kotlin.contracts.InvocationKind
import kotlin.contracts.ExperimentalContracts
import kotlin.contracts.contract
import kotlin.coroutines.Continuation
import kotlin.internal.InlineOnly
import kotlin.internal.KsSymbolName

@KsSymbolName("kk_coroutine_suspended")
private external fun coroutineSuspended(): Any

/**
 * Marker returned by a coroutine that suspended before producing its result.
 * The runtime owns the singleton so the state-machine lowering can compare it
 * by identity with the value returned from the intrinsic block.
 */
@SinceKotlin("1.3")
public val COROUTINE_SUSPENDED: Any
    get() = coroutineSuspended()

/**
 * Internal state markers used by the native coroutine implementation.
 *
 * The runtime currently represents COROUTINE_SUSPENDED with its existing ABI
 * singleton; the enum remains source-backed for the Kotlin API surface.
 */
@SinceKotlin("1.3")
@PublishedApi
internal enum class CoroutineSingletons {
    COROUTINE_SUSPENDED,
    UNDECIDED,
    RESUMED
}

/**
 * Intrinsic entry point used by coroutine lowering to execute [block] with
 * the current continuation and return either its value or the suspension marker.
 */
@SinceKotlin("1.3")
@InlineOnly
@OptIn(ExperimentalContracts::class)
public suspend inline fun <T> suspendCoroutineUninterceptedOrReturn(crossinline block: (Continuation<T>) -> Any?): T {
    contract { callsInPlace(block, InvocationKind.EXACTLY_ONCE) }
    throw NotImplementedError("Implementation of suspendCoroutineUninterceptedOrReturn is intrinsic")
}

/**
 * Fallback used when a suspend function value is not already a compiler-generated
 * continuation implementation.
 */
@Suppress("UNCHECKED_CAST")
@PublishedApi
internal fun <T> startCoroutineUninterceptedOrReturnFallback(
    function: suspend () -> T,
    completion: Continuation<T>
): Any? {
    return (function as Function1<Continuation<T>, Any?>).invoke(completion)
}

/** Receiver-bearing fallback for [startCoroutineUninterceptedOrReturnFallback]. */
@Suppress("UNCHECKED_CAST")
@PublishedApi
internal fun <R, T> startCoroutineUninterceptedOrReturnFallback(
    function: suspend R.() -> T,
    receiver: R,
    completion: Continuation<T>
): Any? {
    return (function as Function2<Any?, Any?, Any?>).invoke(receiver, completion)
}

/**
 * The runtime continuation is already suitable for KSwiftK's coroutine ABI.
 * Keep this source-backed helper as the identity adaptation until a distinct
 * ContinuationImpl representation is required by the runtime.
 */
@PublishedApi
internal fun <T> wrapWithContinuationImpl(completion: Continuation<T>): Continuation<T> = completion
