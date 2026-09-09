@file:OptIn(kotlin.native.concurrent.ObsoleteWorkersApi::class)

package kotlin.native.internal

import kotlin.internal.KsSymbolName
import kotlin.native.concurrent.Future
import kotlin.native.concurrent.TransferMode
import kotlin.native.concurrent.Worker
import kotlinx.cinterop.CFunction
import kotlinx.cinterop.CPointer

@KsSymbolName("__kk_native_concurrent_attach_object_graph")
internal external fun __nativeConcurrentAttachObjectGraph(stable: NativePtr): Any?

@KsSymbolName("__kk_native_concurrent_consume_future")
internal external fun __nativeConcurrentConsumeFuture(id: Int): Any?

@KsSymbolName("__kk_native_concurrent_detach_object_graph")
internal external fun __nativeConcurrentDetachObjectGraph(mode: Int, value: Any?): NativePtr

@KsSymbolName("__kk_native_concurrent_execute_impl")
internal external fun __nativeConcurrentExecuteImpl(
    worker: Worker,
    mode: TransferMode,
    jobArgument: Any?,
    job: CPointer<CFunction<*>>
): Future<Any?>

@PublishedApi
@KsSymbolName("__kk_native_concurrent_start_worker")
internal external fun __nativeConcurrentStartWorker(
    errorReporting: Boolean,
    name: String?
): Worker

@PublishedApi
@KsSymbolName("__kk_native_concurrent_terminate_worker")
internal external fun __nativeConcurrentTerminateWorker(worker: Worker): Unit

@KsSymbolName("__kk_native_concurrent_wait_for_multiple_futures")
internal external fun <T> __nativeConcurrentWaitForMultipleFutures(
    futures: Collection<Future<T>>,
    timeoutMillis: Int
): Set<Future<T>>

@KsSymbolName("__kk_native_concurrent_wait_worker_termination")
internal external fun __nativeConcurrentWaitWorkerTermination(worker: Worker): Unit
