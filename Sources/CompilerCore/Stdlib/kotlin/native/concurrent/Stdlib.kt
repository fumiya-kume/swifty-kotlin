/*
 * Copyright 2010-2023 JetBrains s.r.o. and Kotlin Programming Language contributors.
 * Licensed under the Apache License, Version 2.0.
 *
 * Derived from kotlin-native <kotlin-native/runtime/src/main/kotlin/kotlin/native/concurrent/>.
 */

@file:Suppress("DEPRECATION_ERROR")

package kotlin.native.concurrent

import kotlin.native.internal.ExportForCompiler
import kotlin.native.internal.InternalForKotlinNative
import kotlin.native.internal.NativePtr
import kotlin.native.internal.__nativeConcurrentAttachObjectGraph
import kotlin.native.internal.__nativeConcurrentConsumeFuture
import kotlin.native.internal.__nativeConcurrentDetachObjectGraph
import kotlin.native.internal.__nativeConcurrentExecuteImpl
import kotlin.native.internal.__nativeConcurrentStartWorker
import kotlin.native.internal.__nativeConcurrentTerminateWorker
import kotlin.native.internal.__nativeConcurrentWaitForMultipleFutures
import kotlin.native.internal.__nativeConcurrentWaitWorkerTermination
import kotlinx.cinterop.CFunction
import kotlinx.cinterop.CPointer

@Deprecated(
    "Support for the legacy memory manager has been completely removed. Use lazy() instead.",
    ReplaceWith("lazy(initializer)")
)
@DeprecatedSinceKotlin(errorSince = "2.1")
public fun <T> atomicLazy(initializer: () -> T): Lazy<T> = lazy(initializer)

@PublishedApi
@ObsoleteWorkersApi
internal fun attachObjectGraphInternal(stable: NativePtr): Any? =
    __nativeConcurrentAttachObjectGraph(stable)

@PublishedApi
@ObsoleteWorkersApi
internal fun consumeFuture(id: Int): Any? = __nativeConcurrentConsumeFuture(id)

@PublishedApi
@ObsoleteWorkersApi
internal fun detachObjectGraphInternal(mode: Int, producer: () -> Any?): NativePtr =
    __nativeConcurrentDetachObjectGraph(mode, producer())

@PublishedApi
@ExportForCompiler
@ObsoleteWorkersApi
internal fun executeImpl(
    worker: Worker,
    mode: TransferMode,
    producer: () -> Any?,
    job: CPointer<CFunction<*>>
): Future<Any?> = __nativeConcurrentExecuteImpl(worker, mode, producer(), job)

@Deprecated(
    "Support for the legacy memory manager has been completely removed. Usages of this function can be safely dropped.",
    ReplaceWith("this")
)
@DeprecatedSinceKotlin(errorSince = "2.1")
public fun <T> T.freeze(): T = this

@ObsoleteWorkersApi
public fun <T> waitForMultipleFutures(
    futures: Collection<Future<T>>,
    timeoutMillis: Int
): Set<Future<T>> = __nativeConcurrentWaitForMultipleFutures(futures, timeoutMillis)

@InternalForKotlinNative
@ObsoleteWorkersApi
public fun waitWorkerTermination(worker: Worker): Unit =
    __nativeConcurrentWaitWorkerTermination(worker)

@ObsoleteWorkersApi
public inline fun <R> withWorker(
    name: String? = null,
    errorReporting: Boolean = true,
    block: Worker.() -> R
): R {
    val worker = __nativeConcurrentStartWorker(errorReporting, name)
    try {
        return worker.block()
    } finally {
        __nativeConcurrentTerminateWorker(worker)
    }
}
