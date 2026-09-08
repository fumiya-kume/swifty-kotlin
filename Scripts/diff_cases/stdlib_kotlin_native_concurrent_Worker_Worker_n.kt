// SKIP-DIFF (DEBT-DIFF-001): kotlin.native.concurrent APIs require a Kotlin/Native reference target.
@file:OptIn(
    kotlin.native.concurrent.ObsoleteWorkersApi::class,
    kotlin.ExperimentalStdlibApi::class
)

import kotlinx.cinterop.COpaquePointer
import kotlin.native.concurrent.Future
import kotlin.native.concurrent.TransferMode
import kotlin.native.concurrent.Worker

fun workerReceiverSurface(worker: Worker, other: Any?): Any? {
    val id: Int = worker.id
    val name: String = worker.name
    val equal: Boolean = worker.equals(other)
    val hash: Int = worker.hashCode()
    val text: String = worker.toString()
    val pointer: COpaquePointer? = worker.asCPointer()
    val future: Future<Int> = worker.execute(TransferMode.SAFE, { id }) { it + hash }
    val termination: Future<Unit> = worker.requestTermination(false)
    worker.executeAfter { }
    val processed: Boolean = worker.processQueue()
    val parked: Boolean = worker.park(0L)
    val platformThread: ULong = worker.platformThreadId
    return if (equal || processed || parked || platformThread != 0UL) {
        pointer ?: text
    } else {
        future.result
        termination.result
        name
    }
}

fun main() {}
