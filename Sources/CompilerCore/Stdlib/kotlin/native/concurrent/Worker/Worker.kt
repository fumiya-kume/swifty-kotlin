@file:OptIn(ExperimentalForeignApi::class, ObsoleteWorkersApi::class)

package kotlin.native.concurrent

import kotlin.internal.KsSymbolName
import kotlinx.cinterop.COpaquePointer
import kotlinx.cinterop.ExperimentalForeignApi

// KSP-1250: Worker receiver APIs are Kotlin source backed. The runtime-only
// pieces remain private bridges so the public surface follows Kotlin/Native's
// declarations without exposing synthetic member stubs.

@KsSymbolName("kk_worker_id")
private external fun Worker.__kkWorkerId(): Int

@KsSymbolName("kk_worker_name")
private external fun Worker.__kkWorkerName(): String?

@KsSymbolName("kk_worker_execute")
private external fun <T1, T2> Worker.__kkWorkerExecute(
    mode: TransferMode,
    producer: () -> T1,
    job: (T1) -> T2
): Future<T2>

@KsSymbolName("kk_worker_request_termination")
private external fun Worker.__kkWorkerRequestTermination(
    processScheduledJobs: Boolean
): Future<Unit>

@KsSymbolName("kk_worker_execute_after")
private external fun Worker.__kkWorkerExecuteAfter(
    afterMicroseconds: Long,
    operation: () -> Unit
): Int

@KsSymbolName("kk_worker_process_queue")
private external fun Worker.__kkWorkerProcessQueue(): Int

@KsSymbolName("kk_worker_park")
private external fun Worker.__kkWorkerPark(timeoutMicroseconds: Long, process: Boolean): Int

@KsSymbolName("kk_worker_platform_thread_id")
private external fun Worker.__kkWorkerPlatformThreadId(): ULong

@KsSymbolName("kk_worker_as_cpointer")
private external fun Worker.__kkWorkerAsCPointer(): COpaquePointer?

public val Worker.id: Int
    get() = __kkWorkerId()

public val Worker.name: String
    get() = __kkWorkerName() ?: "worker $id"

public fun Worker.executeAfter(afterMicroseconds: Long = 0L, operation: () -> Unit): Unit {
    if (afterMicroseconds < 0L) {
        throw IllegalArgumentException("Timeout parameter must be non-negative")
    }
    __kkWorkerExecuteAfter(afterMicroseconds, operation)
}

@IgnorableReturnValue
public fun Worker.processQueue(): Boolean = __kkWorkerProcessQueue() != 0

@IgnorableReturnValue
public fun Worker.park(timeoutMicroseconds: Long, process: Boolean = false): Boolean {
    if (timeoutMicroseconds < -1L) {
        throw IllegalArgumentException()
    }
    return __kkWorkerPark(timeoutMicroseconds, process) != 0
}

@ExperimentalStdlibApi
public val Worker.platformThreadId: ULong
    get() = __kkWorkerPlatformThreadId()

@Deprecated("Use kotlinx.cinterop.StableRef instead", level = DeprecationLevel.WARNING)
public fun Worker.asCPointer(): COpaquePointer? = __kkWorkerAsCPointer()

public fun <T1, T2> Worker.execute(
    mode: TransferMode,
    producer: () -> T1,
    job: (T1) -> T2
): Future<T2> = __kkWorkerExecute(mode, producer, job)

public fun Worker.requestTermination(processScheduledJobs: Boolean = true): Future<Unit> =
    __kkWorkerRequestTermination(processScheduledJobs)

public fun Worker.equals(other: Any?): Boolean =
    other is Worker && id == (other as Worker).id

public fun Worker.hashCode(): Int = id

public fun Worker.toString(): String = "Worker $name"
